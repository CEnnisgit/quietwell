import SwiftUI

@main
struct QuietwellApp: App {
    @State private var store = StoreManager()
    @State private var analytics = LocalAnalytics()
    @State private var sound = SoundEngine()
    @State private var mixes = MixLibrary()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(analytics)
                .environment(sound)
                .environment(mixes)
                .preferredColorScheme(.dark)
                .task {
                    #if DEBUG
                    if DebugHooks.forcePro { store.debugForcePro = true }
                    #endif
                    analytics.log("app_open")
                    await store.start()
                }
        }
    }
}
