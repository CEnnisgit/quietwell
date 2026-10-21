import Foundation

#if DEBUG
/// Screenshot hooks (DEBUG builds only). Launch with `-AppScreen <hook>` (and optionally
/// `-AppPro YES`); the app opens that screen and writes Documents/app-state.json with
/// `"ready": "true"` so scripts/sim/capture.sh knows when to take the screenshot.
@MainActor
enum DebugHooks {
    static var screen: String? { UserDefaults.standard.string(forKey: "AppScreen") }
    static var forcePro: Bool { UserDefaults.standard.bool(forKey: "AppPro") }

    private static var values: [String: String] = [:]

    static func report(_ pairs: [String: String]) {
        guard screen != nil else { return }
        for (k, v) in pairs { values[k] = v }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(values) else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? data.write(to: dir.appendingPathComponent("app-state.json"), options: .atomic)
    }
}
#endif
