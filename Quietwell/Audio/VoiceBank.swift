import Foundation

/// Up to four generated layers mixed into one mono stream.
///
/// The main actor writes targets (kind, params, volume, master gain) into preallocated slots; the
/// audio thread reads them and owns the generators. Slots are fixed-size raw memory, so neither
/// side ever allocates or resizes while the other is reading. Individual fields may be read a
/// buffer late, which only delays a parameter change by a few milliseconds.
final class VoiceBank: @unchecked Sendable {
    static let maxLayers = 4

    struct Target {
        var active = false
        var kindIndex = 0
        var tone: Float = 0.5
        var intensity: Float = 0.5
        var volume: Float = 0.8
        var generation = 0
    }

    private struct Voice {
        var generator: SoundGenerator
        var generation = -1
        var volume: Float = 0
        var active = false
    }

    let sampleRate: Float
    private let targets: UnsafeMutablePointer<Target>
    private let voices: UnsafeMutablePointer<Voice>
    /// Written by the main actor; smoothed per sample on the audio thread.
    private var masterTarget: Float = 0
    private var master: Float = 0
    private let smoothing: Float

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        targets = .allocate(capacity: Self.maxLayers)
        targets.initialize(repeating: Target(), count: Self.maxLayers)
        voices = .allocate(capacity: Self.maxLayers)
        voices.initialize(repeating: Voice(generator: SoundGenerator(kind: .white, sampleRate: sampleRate)),
                          count: Self.maxLayers)
        // ~50 ms parameter glide
        smoothing = 1 - OnePole.coefficient(cutoff: 20, sampleRate: sampleRate)
    }

    deinit {
        targets.deinitialize(count: Self.maxLayers); targets.deallocate()
        voices.deinitialize(count: Self.maxLayers); voices.deallocate()
    }

    // MARK: Main-actor side

    func setLayer(_ slot: Int, kind: SoundKind, params: SoundParams, volume: Float) {
        guard (0..<Self.maxLayers).contains(slot) else { return }
        var t = targets[slot]
        if !t.active || t.kindIndex != kind.index { t.generation &+= 1 }
        t.active = true
        t.kindIndex = kind.index
        t.tone = params.tone
        t.intensity = params.intensity
        t.volume = volume
        targets[slot] = t
    }

    func clearLayer(_ slot: Int) {
        guard (0..<Self.maxLayers).contains(slot) else { return }
        targets[slot].active = false
    }

    func clearAll() { for i in 0..<Self.maxLayers { targets[i].active = false } }

    func setMasterGain(_ gain: Float) { masterTarget = min(max(gain, 0), 1) }
    var masterGainTarget: Float { masterTarget }

    // MARK: Audio-thread side

    func render(into out: UnsafeMutablePointer<Float>, count: Int) {
        for i in 0..<count { out[i] = 0 }
        for s in 0..<Self.maxLayers {
            let t = targets[s]
            if t.active && voices[s].generation != t.generation {
                voices[s].generator = SoundGenerator(kind: SoundKind.from(index: t.kindIndex), sampleRate: sampleRate,
                                                     seed: UInt32(truncatingIfNeeded: 0xA5A5 &+ s &* 101 &+ t.generation),
                                                     params: SoundParams(tone: t.tone, intensity: t.intensity))
                voices[s].generation = t.generation
                voices[s].volume = 0
            }
            let targetVolume: Float = t.active ? t.volume : 0
            if !t.active && voices[s].volume < 0.0001 { voices[s].volume = 0; continue }
            voices[s].generator.setParams(SoundParams(tone: t.tone, intensity: t.intensity))
            var v = voices[s].volume
            for i in 0..<count {
                v += (targetVolume - v) * smoothing
                out[i] += voices[s].generator.nextSample() * v
            }
            voices[s].volume = v
        }
        var m = master
        let target = masterTarget
        for i in 0..<count {
            m += (target - m) * smoothing
            out[i] = clampUnit(out[i] * m)
        }
        master = m
    }
}
