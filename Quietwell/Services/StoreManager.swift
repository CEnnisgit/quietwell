import Foundation
import StoreKit
import Observation

/// StoreKit 2 entitlement manager configured by `AppConfig.ProductID`.
@MainActor
@Observable
final class StoreManager {
    private(set) var products: [String: Product] = [:]
    private(set) var purchasedProductIDs: Set<String> = []
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    /// Purchase / restore problems, shown as an alert.
    var errorMessage: String?
    /// Why prices are missing (no StoreKit configuration, offline). Shown inline, never as an alert.
    private(set) var productLoadError: String?
    #if DEBUG
    /// Screenshot hooks only (`-AppPro YES`).
    var debugForcePro = false
    #endif

    var isPro: Bool {
        #if DEBUG
        if debugForcePro { return true }
        #endif
        return Self.isEntitled(purchasedProductIDs)
    }

    var activePlanName: String? {
        #if DEBUG
        if debugForcePro && purchasedProductIDs.isEmpty { return "Yearly" }
        #endif
        return Self.planName(for: purchasedProductIDs)
    }

    nonisolated static func isEntitled(_ ids: Set<String>) -> Bool {
        !ids.isDisjoint(with: AppConfig.ProductID.all)
    }

    /// Lifetime wins over Yearly, Yearly over Monthly.
    nonisolated static func planName(for ids: Set<String>) -> String? {
        if ids.contains(AppConfig.ProductID.lifetime) { return "Lifetime" }
        if ids.contains(AppConfig.ProductID.yearly) { return "Yearly" }
        if ids.contains(AppConfig.ProductID.monthly) { return "Monthly" }
        return nil
    }

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    func start() async {
        guard !started else { return }
        started = true
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        await refreshEntitlements()
        await loadProducts()
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: AppConfig.ProductID.all)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            productLoadError = loaded.isEmpty ? "Prices aren't available right now." : nil
        } catch {
            productLoadError = "Couldn't load prices. \(error.localizedDescription)"
        }
    }

    func refreshEntitlements() async {
        var ids = Set<String>()
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.revocationDate == nil {
                ids.insert(transaction.productID)
            }
        }
        purchasedProductIDs = ids
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorMessage = "The purchase couldn't be verified."
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                return true
            case .pending, .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshEntitlements()
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        await transaction.finish()
        await refreshEntitlements()
    }
}
