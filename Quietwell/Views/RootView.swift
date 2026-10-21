import SwiftUI

enum AppRoute: Hashable {
    case settings
    case mix
}

struct RootView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @Environment(LocalAnalytics.self) private var analytics
    @Environment(StoreManager.self) private var store
    @Environment(SoundEngine.self) private var sound
    @State private var path: [AppRoute] = []
    @State private var showPaywall = false
    @State private var showTimer = false
    @State private var didRunDebugHook = false

    var body: some View {
        Group {
            if hasOnboarded {
                NavigationStack(path: $path) {
                    HomeView(showPaywall: $showPaywall, showTimer: $showTimer, path: $path)
                        .navigationDestination(for: AppRoute.self) { route in
                            switch route {
                            case .settings: SettingsView(showPaywall: $showPaywall)
                            case .mix: MixView(showPaywall: $showPaywall)
                            }
                        }
                }
            } else {
                OnboardingView {
                    analytics.log("onboarding_done")
                    hasOnboarded = true
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .onAppear { analytics.log("paywall_view") }
        }
        .sheet(isPresented: $showTimer) {
            TimerSheet(showPaywall: $showPaywall)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: store.isPro) { _, isPro in if !isPro { sound.enforceFreeTier() } }
        .task { await runDebugHook() }
    }

    private func runDebugHook() async {
        #if DEBUG
        guard !didRunDebugHook, let screen = DebugHooks.screen else { return }
        didRunDebugHook = true
        // Hooks: onboarding | home | mix | timer | paywall | settings
        switch screen {
        case "onboarding": hasOnboarded = false
        case "home":
            hasOnboarded = true
            sound.select(.brown, mixing: false)
        case "mix":
            hasOnboarded = true
            sound.load([MixLayer(kind: .brown, params: SoundParams(tone: 0.35, intensity: 0.6), volume: 0.8),
                        MixLayer(kind: .rain, params: SoundParams(tone: 0.5, intensity: 0.3), volume: 0.5),
                        MixLayer(kind: .fan, params: SoundParams(tone: 0.4, intensity: 0.4), volume: 0.35)])
            path = [.mix]
        case "timer":
            hasOnboarded = true
            sound.select(.pink, mixing: false)
            sound.startTimer(15 * 60)
            showTimer = true
        case "paywall": hasOnboarded = true; showPaywall = true
        case "settings": hasOnboarded = true; path = [.settings]
        default: hasOnboarded = true
        }
        try? await Task.sleep(for: .seconds(2))
        DebugHooks.report(["screen": screen, "ready": "true",
                           "playing": sound.isPlaying ? "true" : "false",
                           "layers": sound.title,
                           "pro": store.isPro ? "true" : "false",
                           "engineError": sound.engineError ?? ""])
        #endif
    }
}
