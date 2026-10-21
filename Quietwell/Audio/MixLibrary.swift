import Foundation
import Observation

struct SavedMix: Codable, Sendable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var layers: [MixLayer]
}

/// Pro: saved mixes, stored as JSON in UserDefaults on this iPhone.
@MainActor
@Observable
final class MixLibrary {
    static let storageKey = "savedMixes.v1"

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var mixes: [SavedMix]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([SavedMix].self, from: data) {
            mixes = decoded
        } else {
            mixes = []
        }
    }

    static func suggestedName(for layers: [MixLayer]) -> String {
        layers.map(\.kind.title).joined(separator: " + ")
    }

    func save(_ layers: [MixLayer], name: String? = nil) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        mixes.insert(SavedMix(name: trimmed.isEmpty ? Self.suggestedName(for: layers) : trimmed, layers: layers), at: 0)
        persist()
    }

    func delete(_ mix: SavedMix) {
        mixes.removeAll { $0.id == mix.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(mixes) { defaults.set(data, forKey: Self.storageKey) }
    }
}
