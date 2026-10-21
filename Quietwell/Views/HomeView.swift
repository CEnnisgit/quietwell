import SwiftUI

struct HomeView: View {
    @Binding var showPaywall: Bool
    @Binding var showTimer: Bool
    @Binding var path: [AppRoute]
    @Environment(StoreManager.self) private var store
    @Environment(SoundEngine.self) private var sound
    @Environment(LocalAnalytics.self) private var analytics

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                playCard
                if let layer = sound.layers.first { ShapeControls(layer: layer) }
                Text("SOUNDS")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(SoundKind.allCases) { kind in
                        SoundTile(kind: kind,
                                  isOn: sound.isPlaying && sound.layers.contains { $0.kind == kind },
                                  isLocked: !kind.isFree && !store.isPro) {
                            tap(kind)
                        }
                    }
                }
                Label("Generated live on your iPhone. Works offline.", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Quietwell")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if store.isPro { path.append(.mix) } else { showPaywall = true }
                } label: { Label("Mix", systemImage: "square.3.layers.3d") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { path.append(.settings) } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
        }
    }

    private func tap(_ kind: SoundKind) {
        guard kind.isFree || store.isPro else {
            showPaywall = true
            return
        }
        analytics.log("play_\(kind.rawValue)")
        sound.select(kind, mixing: store.isPro)
    }

    private var playCard: some View {
        VStack(spacing: 14) {
            Text(sound.title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Button { sound.toggle() } label: {
                Image(systemName: sound.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 34, weight: .bold))
                    .frame(width: 84, height: 84)
                    .background(Color.accentColor, in: Circle())
                    .foregroundStyle(.white)
            }
            .accessibilityLabel(sound.isPlaying ? "Pause" : "Play")
            Button { showTimer = true } label: {
                Label(timerText, systemImage: "moon.zzz")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))
    }

    private var timerText: String {
        if let _ = sound.timer { return "Sleep timer · \(SleepTimer.countdown(sound.timerRemaining))" }
        return "Sleep timer · Off"
    }
}

struct SoundTile: View {
    let kind: SoundKind
    let isOn: Bool
    let isLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: kind.icon)
                    .font(.title2)
                    .frame(height: 30)
                Text(kind.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background(isOn ? Color.accentColor : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .topTrailing) {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLocked ? "\(kind.title), Pro" : kind.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Tone / intensity (and, in a mix, volume) sliders for one layer.
struct ShapeControls: View {
    let layer: MixLayer
    var showVolume = false
    @Environment(SoundEngine.self) private var sound

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showVolume {
                slider("Volume", value: layer.volume) { var l = layer; l.volume = $0; sound.update(l) }
            }
            slider(layer.kind.toneLabel, value: layer.params.tone) { var l = layer; l.params.tone = $0; sound.update(l) }
            slider(layer.kind.intensityLabel, value: layer.params.intensity) { var l = layer; l.params.intensity = $0; sound.update(l) }
        }
        .padding(16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }

    private func slider(_ title: String, value: Float, set: @escaping (Float) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Slider(value: Binding(get: { Double(value) }, set: { set(Float($0)) }), in: 0...1)
                .accessibilityLabel(title)
        }
    }
}
