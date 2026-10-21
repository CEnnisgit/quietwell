import XCTest
@testable import Quietwell

/// Pure-logic tests. StoreKit purchases and the UI are covered by the sim-proof screenshot job.
final class AppConfigTests: XCTestCase {
    func testProductIDsAreUniqueAndScopedToBundle() {
        let ids = AppConfig.ProductID.all
        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(Set(ids).count, 3)
        for id in ids { XCTAssertTrue(id.hasPrefix(AppConfig.bundleID + ".pro."), id) }
    }

    func testNoWeeklyPlan() {
        XCTAssertFalse(AppConfig.ProductID.all.contains { $0.lowercased().contains("week") })
    }

    func testEveryProductHasDebugFallbackPrice() {
        for id in AppConfig.ProductID.all { XCTAssertNotNil(AppConfig.debugFallbackPrices[id], id) }
    }

    func testOnboardingHasThreePages() {
        XCTAssertEqual(AppConfig.onboardingPages.count, 3)
    }

    func testLinksAreHTTPS() {
        for url in [AppConfig.Links.privacy, AppConfig.Links.support, AppConfig.Links.terms] {
            XCTAssertEqual(url.scheme, "https")
        }
    }
}

final class EntitlementTests: XCTestCase {
    func testEntitlement() {
        XCTAssertFalse(StoreManager.isEntitled([]))
        XCTAssertFalse(StoreManager.isEntitled(["com.example.other"]))
        XCTAssertTrue(StoreManager.isEntitled([AppConfig.ProductID.monthly]))
    }

    func testPlanNamePriority() {
        XCTAssertNil(StoreManager.planName(for: []))
        XCTAssertEqual(StoreManager.planName(for: [AppConfig.ProductID.monthly]), "Monthly")
        XCTAssertEqual(StoreManager.planName(for: [AppConfig.ProductID.monthly, AppConfig.ProductID.yearly]), "Yearly")
        XCTAssertEqual(StoreManager.planName(for: Set(AppConfig.ProductID.all)), "Lifetime")
    }
}

final class LocalAnalyticsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "analytics-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @MainActor func testCountsAndPersists() {
        let d = freshDefaults()
        let a = LocalAnalytics(defaults: d)
        a.log("open"); a.log("open"); a.log("tap")
        XCTAssertEqual(a.count("open"), 2)
        XCTAssertEqual(a.total, 3)
        let b = LocalAnalytics(defaults: d)
        XCTAssertEqual(b.count("open"), 2)
        XCTAssertEqual(b.count("missing"), 0)
    }

    @MainActor func testReset() {
        let d = freshDefaults()
        let a = LocalAnalytics(defaults: d)
        a.log("x")
        a.reset()
        XCTAssertEqual(a.total, 0)
        XCTAssertEqual(LocalAnalytics(defaults: d).total, 0)
    }
}
