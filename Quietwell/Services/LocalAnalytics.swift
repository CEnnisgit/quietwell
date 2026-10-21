import Foundation
import Observation

/// On-device-only usage counter. Events are counted in UserDefaults on this iPhone and are never
/// sent anywhere (no network, no SDK), so the privacy label stays "Data Not Collected".
@MainActor
@Observable
final class LocalAnalytics {
    static let storageKey = "localAnalytics.counts"

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var counts: [String: Int]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.counts = (defaults.dictionary(forKey: Self.storageKey) as? [String: Int]) ?? [:]
    }

    func log(_ event: String) {
        counts[event, default: 0] += 1
        defaults.set(counts, forKey: Self.storageKey)
    }

    func count(_ event: String) -> Int { counts[event] ?? 0 }

    var total: Int { counts.values.reduce(0, +) }

    func reset() {
        counts = [:]
        defaults.removeObject(forKey: Self.storageKey)
    }
}
