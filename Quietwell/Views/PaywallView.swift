import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selected: Plan = .yearly

    enum Plan: CaseIterable, Identifiable {
        case yearly, lifetime, monthly   // display order; no weekly plan
        var id: Self { self }
        var productID: String {
            switch self {
            case .yearly: AppConfig.ProductID.yearly
            case .lifetime: AppConfig.ProductID.lifetime
            case .monthly: AppConfig.ProductID.monthly
            }
        }
        var title: String {
            switch self { case .yearly: "Yearly"; case .lifetime: "Lifetime"; case .monthly: "Monthly" }
        }
        var subtitle: String {
            switch self {
            case .yearly: "Billed once a year"
            case .lifetime: "Pay once, keep Pro"
            case .monthly: "Billed every month"
            }
        }
    }

    private func price(_ plan: Plan) -> String? {
        if let p = store.products[plan.productID] { return p.displayPrice }
        #if DEBUG
        return AppConfig.debugFallbackPrices[plan.productID]
        #else
        return nil
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                benefits
                plans
                Button {
                    Task {
                        guard let product = store.products[selected.productID] else {
                            store.errorMessage = "Prices aren't available right now. Please try again later."
                            return
                        }
                        if await store.purchase(product) { dismiss() }
                    }
                } label: {
                    Group {
                        if store.isPurchasing { ProgressView() } else { Text("Continue").font(.headline) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isPurchasing)

                Text(AppConfig.freeTierSummary)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                disclosure
                links
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(.tertiarySystemFill), in: Circle())
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
            .padding(.trailing, 12)
            .padding(.top, 8)
        }
        .alert("Purchase", isPresented: Binding(get: { store.errorMessage != nil },
                                                set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.errorMessage ?? "") }
        .onChange(of: store.isPro) { _, isPro in if isPro { dismiss() } }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(AppConfig.proName)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            Text(AppConfig.paywallTagline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(AppConfig.proBenefits) { b in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: b.icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.title).font(.body.weight(.semibold))
                        Text(b.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var plans: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CHOOSE A PLAN")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Plan.allCases) { plan in
                Button { selected = plan } label: { planRow(plan) }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected == plan ? .isSelected : [])
            }
        }
    }

    private func planRow(_ plan: Plan) -> some View {
        let isSelected = selected == plan
        let p = price(plan)
        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? Color.accentColor : Color(.separator))
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.title).font(.body.weight(.semibold))
                Text(plan.subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                switch plan {
                case .yearly: Text(p.map { "\($0)/year" } ?? "—")
                case .monthly: Text(p.map { "\($0)/month" } ?? "—")
                case .lifetime:
                    Text(p ?? "—")
                    Text("one-time").font(.caption).foregroundStyle(.secondary)
                }
            }
            .font(.body.weight(.semibold))
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        }
        .contentShape(Rectangle())
    }

    private var disclosure: some View {
        let yearly = price(.yearly).map { " Yearly is \($0) per year." } ?? ""
        let monthly = price(.monthly).map { " Monthly is \($0) per month." } ?? ""
        return Text("Payment is charged to your Apple Account at confirmation.\(yearly)\(monthly) Subscriptions renew automatically unless canceled at least 24 hours before the end of the current period, and your account is charged for renewal within 24 hours before the period ends. Manage or cancel anytime in Settings › [your name] › Subscriptions. Lifetime is a one-time purchase and doesn't renew.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private var links: some View {
        VStack(spacing: 4) {
            Button("Restore Purchases") { Task { await store.restore() } }
                .frame(minHeight: 44)
            HStack(spacing: 16) {
                Button("Terms of Use") { openURL(AppConfig.Links.terms) }
                Button("Privacy Policy") { openURL(AppConfig.Links.privacy) }
                Button("Support") { openURL(AppConfig.Links.support) }
            }
            .frame(minHeight: 44)
        }
        .font(.footnote.weight(.semibold))
    }
}
