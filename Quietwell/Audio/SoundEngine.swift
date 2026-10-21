import Foundation
import AVFoundation
import MediaPlayer
import Observation

struct MixLayer: Codable, Sendable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var kind: SoundKind
    var params = SoundParams()
    var volume: Float = 0.8
}

/// Owns the AVAudioEngine graph (one AVAudioSourceNode fed by `VoiceBank`), the sleep timer,
/// background playback and the Lock Screen / Control Center controls.
@MainActor
@Observable
final class SoundEngine {
    private(set) var layers: [MixLayer] = [MixLayer(kind: .brown)]
    private(set) var isPlaying = false
    private(set) var timer: SleepTimer?
    private(set) var timerRemaining: TimeInterval = 0
    /// Set when the audio hardware refused to start (shown inline; playback state is kept).
    private(set) var engineError: String?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var bank: VoiceBank?
    @ObservationIgnored private var sourceNode: AVAudioSourceNode?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var commandsInstalled = false

    /// Used by remote-command handlers, which run outside the main actor's closures.
    static weak var current: SoundEngine?

    init() { Self.current = self }

    var title: String {
        layers.isEmpty ? "Quietwell" : layers.map(\.kind.title).joined(separator: " + ")
    }

    // MARK: Layers

    /// Free: one sound at a time. Pro: toggles the sound in a mix of up to four.
    func select(_ kind: SoundKind, mixing: Bool) {
        if mixing {
            if let i = layers.firstIndex(where: { $0.kind == kind }) {
                if layers.count > 1 { layers.remove(at: i) }
            } else if layers.count < VoiceBank.maxLayers {
                layers.append(MixLayer(kind: kind))
            } else {
                layers[layers.count - 1] = MixLayer(kind: kind)
            }
        } else {
            let params = layers.first(where: { $0.kind == kind })?.params ?? SoundParams()
            layers = [MixLayer(kind: kind, params: params)]
        }
        pushLayers()
        if !isPlaying { play() } else { updateNowPlaying() }
    }

    func update(_ layer: MixLayer) {
        guard let i = layers.firstIndex(where: { $0.id == layer.id }) else { return }
        layers[i] = layer
        pushLayers()
    }

    func remove(_ layer: MixLayer) {
        guard layers.count > 1 else { return }
        layers.removeAll { $0.id == layer.id }
        pushLayers()
        updateNowPlaying()
    }

    func load(_ mix: [MixLayer]) {
        layers = Array(mix.prefix(VoiceBank.maxLayers))
        if layers.isEmpty { layers = [MixLayer(kind: .brown)] }
        pushLayers()
        if !isPlaying { play() } else { updateNowPlaying() }
    }

    /// Drops Pro-only layers when Pro is not active.
    func enforceFreeTier() {
        let allowed = layers.filter { $0.kind.isFree }
        let first = allowed.first ?? MixLayer(kind: .brown)
        if layers != [first] {
            layers = [first]
            pushLayers()
            updateNowPlaying()
        }
    }

    private func pushLayers() {
        guard let bank else { return }
        for slot in 0..<VoiceBank.maxLayers {
            if slot < layers.count {
                let l = layers[slot]
                bank.setLayer(slot, kind: l.kind, params: l.params, volume: l.volume)
            } else {
                bank.clearLayer(slot)
            }
        }
    }

    // MARK: Transport

    func toggle() { isPlaying ? pause() : play() }

    func play() {
        isPlaying = true
        if timer?.isFinished(at: Date()) == true { timer = nil }
        startEngineIfNeeded()
        pushLayers()
        applyGain()
        startTicking()
        updateNowPlaying()
    }

    func pause() {
        isPlaying = false
        bank?.setMasterGain(0)
        tickTask?.cancel(); tickTask = nil
        // Let the 50 ms glide finish before stopping the engine.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !self.isPlaying else { return }
            self.engine.pause()
        }
        updateNowPlaying()
    }

    /// Timer end: fully stops the engine and deactivates the audio session, so nothing keeps
    /// running in the background after the fade-out.
    func stop() {
        isPlaying = false
        bank?.setMasterGain(0)
        tickTask?.cancel(); tickTask = nil
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !self.isPlaying else { return }
            self.engine.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        updateNowPlaying()
    }

    // MARK: Timer

    func startTimer(_ duration: TimeInterval?) {
        timer = duration.map { SleepTimer(duration: $0) }
        timerRemaining = timer?.duration ?? 0
        if !isPlaying { play() } else { applyGain(); startTicking() }
    }

    private func applyGain() {
        let now = Date()
        var g: Float = 1
        if let timer { g = timer.gain(at: now) }
        bank?.setMasterGain(isPlaying ? g : 0)
    }

    private func startTicking() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        let now = Date()
        if let t = timer {
            timerRemaining = t.remaining(at: now)
            if t.isFinished(at: now) {
                // The fade has reached silence: stop the engine and release the audio session.
                timer = nil
                stop()
                return
            }
        }
        applyGain()
    }

    // MARK: Engine

    private func startEngineIfNeeded() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            engineError = "Audio session: \(error.localizedDescription)"
        }
        if bank == nil {
            var sr = engine.outputNode.outputFormat(forBus: 0).sampleRate
            if sr <= 0 { sr = 44_100 }
            let bank = VoiceBank(sampleRate: Float(sr))
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1) else { return }
            let node = Self.makeSourceNode(bank: bank)
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            self.bank = bank
            self.sourceNode = node
        }
        installRemoteCommands()
        guard !engine.isRunning else { return }
        do {
            engine.prepare()
            try engine.start()
            engineError = nil
        } catch {
            engineError = "Couldn't start audio: \(error.localizedDescription)"
        }
    }

    /// Built outside the main actor so the render closure carries no actor isolation:
    /// it runs on the real-time audio thread.
    nonisolated private static func makeSourceNode(bank: VoiceBank) -> AVAudioSourceNode {
        AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let count = Int(frameCount)
            guard let first = buffers.first, let data = first.mData else { return noErr }
            let out = data.assumingMemoryBound(to: Float.self)
            bank.render(into: out, count: count)
            for b in buffers.dropFirst() {
                if let d = b.mData { d.assumingMemoryBound(to: Float.self).update(from: out, count: count) }
            }
            return noErr
        }
    }

    // MARK: Lock Screen / Control Center

    private func installRemoteCommands() {
        guard !commandsInstalled else { return }
        commandsInstalled = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.playCommand.addTarget(handler: Self.remoteHandler { $0.play() })
        center.pauseCommand.addTarget(handler: Self.remoteHandler { $0.pause() })
        center.togglePlayPauseCommand.addTarget(handler: Self.remoteHandler { $0.toggle() })
    }

    /// Remote-command handlers are not main-actor closures; they hop to the main actor.
    nonisolated private static func remoteHandler(
        _ action: @escaping @MainActor @Sendable (SoundEngine) -> Void
    ) -> @Sendable (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        return { _ in
            Task { @MainActor in
                if let engine = SoundEngine.current { action(engine) }
            }
            return .success
        }
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "Quietwell",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let timer {
            info[MPMediaItemPropertyPlaybackDuration] = timer.duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Date().timeIntervalSince(timer.start)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
