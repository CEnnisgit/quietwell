import Foundation

/// Everything app-specific that the shared screens read. `scripts/new-app.sh` renames
/// "Quietwell"/"quietwell"; then edit the copy, benefits and prices here.
enum AppConfig {
    static let appName = "Quietwell"
    static let proName = "Quietwell Pro"
    static let bundleID = "com.nimbuswebdesign.quietwell"

    enum ProductID {
        static let monthly = "com.nimbuswebdesign.quietwell.pro.monthly"
        static let yearly = "com.nimbuswebdesign.quietwell.pro.yearly"
        static let lifetime = "com.nimbuswebdesign.quietwell.pro.lifetime"
        static let all = [monthly, yearly, lifetime]
    }

    /// DEBUG-only paywall prices for Simulator runs launched outside Xcode (no StoreKit config).
    /// Keep in sync with Quietwell.storekit.
    static let debugFallbackPrices: [String: String] = [
        ProductID.monthly: "$2.99",
        ProductID.yearly: "$12.99",
        ProductID.lifetime: "$19.99",
    ]

    enum Links {
        static let privacy = URL(string: "https://cennisgit.github.io/app-pages/apps/quietwell/privacy/")!
        static let support = URL(string: "https://cennisgit.github.io/app-pages/apps/quietwell/support/")!
        /// Apple's standard EULA, used as the Terms of Use for subscriptions.
        static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    }

    static let paywallTagline = "Mix your own sound. Every sound is made live on your iPhone."
    static let freeTierSummary = "Not now? White, pink and brown noise, fan and rain stay free with the sleep timer, with no time limit."
    static let privacySummary = "Every sound is generated on your iPhone. Quietwell has no account, no ads, no analytics SDKs and makes no network requests."

    static let proBenefits: [Benefit] = [
        Benefit(icon: "square.3.layers.3d", title: "Mix up to four sounds", detail: "For example brown noise under light rain."),
        Benefit(icon: "water.waves", title: "More generated sounds", detail: "Ocean, thunder, green noise and a low hum."),
        Benefit(icon: "bookmark", title: "Saved mixes", detail: "Start your favorite mix with one tap."),
        Benefit(icon: "sunrise", title: "Wake-up fade", detail: "Slowly brings the sound back in the morning."),
    ]

    static let onboardingPages: [OnboardingPage] = [
        OnboardingPage(icon: "waveform", title: "Welcome to Quietwell", body: "White, pink and brown noise, fan and rain for sleep, naps and focus."),
        OnboardingPage(icon: "slider.horizontal.3", title: "Made live, shaped by you", body: "Every sound is generated on your iPhone. Adjust tone and intensity until it sounds right."),
        OnboardingPage(icon: "moon.zzz", title: "Set it and drift off", body: "A sleep timer fades the sound out gently. Works offline, no account, no ads."),
    ]
}

struct Benefit: Sendable, Identifiable, Hashable {
    let icon: String
    let title: String
    let detail: String
    var id: String { title }
}

struct OnboardingPage: Sendable, Identifiable, Hashable {
    let icon: String
    let title: String
    let body: String
    var id: String { title }
}
