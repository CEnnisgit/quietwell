import SwiftUI
import StoreKit

struct SettingsView: View {
    @Binding var showPaywall: Bool
    @Environment(StoreManager.self) private var store
    @Environment(LocalAnalytics.self) private var analytics
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @State private var showManageSubscriptions = false
    @State private var restoring = false

    var body: some View {
        List {
            Section(AppConfig.proName) {
                HStack {
                    Label("Status", systemImage: "star.circle")
                    Spacer()
                    Text(store.isPro ? "Pro · \(store.activePlanName ?? "Active")" : "Free")
                        .foregroundStyle(store.isPro ? Color.accentColor : Color.secondary)
                        .fontWeight(.semibold)
                }
                if !store.isPro {
                    Button { showPaywall = true } label: {
                        Label("Upgrade to \(AppConfig.proName)", systemImage: "sparkles")
                    }
                }
                Button {
                    restoring = true
                    Task { await store.restore(); restoring = false }
                } label: {
                    HStack {
                        Label("Restore Purchases", systemImage: "arrow.clockwise")
                        if restoring { Spacer(); ProgressView() }
                    }
                }
                Button { showManageSubscriptions = true } label: {
                    Label("Manage Subscription", systemImage: "creditcard")
                }
                Text("You can also manage or cancel in Settings › [your name] › Subscriptions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Label(AppConfig.privacySummary, systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Actions counted on this iPhone")
                    Spacer()
                    Text("\(analytics.total)").foregroundStyle(.secondary)
                }
                Button("Reset on-device stats", role: .destructive) { analytics.reset() }
            } header: { Text("Privacy") } footer: {
                Text("These counts never leave your device.")
            }

            Section("About") {
                Button("Rate \(AppConfig.appName)") { requestReview() }
                Button("Privacy Policy") { openURL(AppConfig.Links.privacy) }
                Button("Terms of Use") { openURL(AppConfig.Links.terms) }
                Button("Support") { openURL(AppConfig.Links.support) }
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
    }
}
