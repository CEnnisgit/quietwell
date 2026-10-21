import Foundation

/// Every Quietwell sound. All are synthesized live; there are no audio files in the bundle.
enum SoundKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case white, pink, brown, fan, rain, green, ocean, thunder, hum

    var id: String { rawValue }

    /// Free tier: five core sounds with no time limit.
    static let freeKinds: [SoundKind] = [.white, .pink, .brown, .fan, .rain]
    var isFree: Bool { Self.freeKinds.contains(self) }

    var title: String {
        switch self {
        case .white: "White Noise"
        case .pink: "Pink Noise"
        case .brown: "Brown Noise"
        case .fan: "Fan"
        case .rain: "Rain"
        case .green: "Green Noise"
        case .ocean: "Ocean"
        case .thunder: "Thunder"
        case .hum: "Low Hum"
        }
    }

    var icon: String {
        switch self {
        case .white: "waveform"
        case .pink: "waveform.path"
        case .brown: "waveform.path.ecg"
        case .fan: "fan"
        case .rain: "cloud.rain"
        case .green: "leaf"
        case .ocean: "water.waves"
        case .thunder: "cloud.bolt.rain"
        case .hum: "dot.radiowaves.left.and.right"
        }
    }

    /// What the tone and intensity sliders do for this sound.
    var toneLabel: String {
        switch self {
        case .fan: "Size"
        case .rain: "Surface"
        case .ocean: "Depth"
        case .thunder: "Distance"
        case .hum: "Pitch"
        default: "Tone"
        }
    }

    var intensityLabel: String {
        switch self {
        case .fan: "Speed"
        case .rain: "Drizzle to downpour"
        case .ocean: "Waves"
        case .thunder: "Storm"
        default: "Intensity"
        }
    }

    /// Stable index used by the audio thread (no strings or allocations there).
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    static func from(index: Int) -> SoundKind {
        allCases.indices.contains(index) ? allCases[index] : .white
    }
}

/// Per-layer shape controls, both 0...1. Tone 1 is brightest (no extra filtering).
struct SoundParams: Codable, Sendable, Equatable, Hashable {
    var tone: Float = 0.5
    var intensity: Float = 0.5

    static let neutral = SoundParams(tone: 1, intensity: 0.5)
}
