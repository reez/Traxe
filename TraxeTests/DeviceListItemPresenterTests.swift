import XCTest

@testable import Traxe

final class DeviceListItemPresenterTests: XCTestCase {
    func testMakeViewDataFormatsTerahashValueAndUsesMetricsHostname() {
        let viewData = DeviceListItemPresenter.makeViewData(
            device: SavedDevice(name: "Fallback Miner", ipAddress: "192.168.1.10"),
            metrics: DeviceMetrics(hashrate: 1_340, hostname: "Alpha Miner"),
            index: 0,
            reachableIPs: ["192.168.1.10"],
            isLoadingAggregatedStats: false,
            subscriptionAccessPolicy: makeLoadedFreePolicy(),
            isPreview: false
        )

        XCTAssertEqual(viewData.title, "Alpha Miner")
        XCTAssertEqual(viewData.hashrateValue, 1.34, accuracy: 0.001)
        XCTAssertEqual(viewData.hashrateValueText, "1.3")
        XCTAssertEqual(viewData.hashrateUnitText, "TH/s")
        XCTAssertEqual(viewData.summaryHashrateText, "1.3 TH/s")
        XCTAssertFalse(viewData.showsPlaceholderHashrate)
        XCTAssertTrue(viewData.isReachable)
        XCTAssertTrue(viewData.isAccessible)
        XCTAssertFalse(viewData.showsLock)
    }

    func testMakeViewDataShowsLockForInaccessibleLoadedSubscriptionDeviceWithMetrics() {
        let viewData = DeviceListItemPresenter.makeViewData(
            device: SavedDevice(name: "Locked Miner", ipAddress: "192.168.1.11"),
            metrics: DeviceMetrics(hashrate: 950),
            index: 1,
            reachableIPs: [],
            isLoadingAggregatedStats: false,
            subscriptionAccessPolicy: makeLoadedFreePolicy(),
            isPreview: false
        )

        XCTAssertEqual(viewData.hashrateValueText, "950.0")
        XCTAssertEqual(viewData.hashrateUnitText, "GH/s")
        XCTAssertFalse(viewData.isAccessible)
        XCTAssertFalse(viewData.isReachable)
        XCTAssertTrue(viewData.showsLock)
    }

    func testMakeViewDataUsesPlaceholderStateWithoutMetricsAndDoesNotShowLock() {
        let viewData = DeviceListItemPresenter.makeViewData(
            device: SavedDevice(name: "Offline Miner", ipAddress: "192.168.1.12"),
            metrics: nil,
            index: 2,
            reachableIPs: [],
            isLoadingAggregatedStats: false,
            subscriptionAccessPolicy: makeLoadedFreePolicy(),
            isPreview: false
        )

        XCTAssertEqual(viewData.title, "Offline Miner")
        XCTAssertEqual(viewData.hashrateValue, 0, accuracy: 0.001)
        XCTAssertEqual(viewData.hashrateValueText, "---")
        XCTAssertEqual(viewData.hashrateUnitText, "GH/s")
        XCTAssertNil(viewData.summaryHashrateText)
        XCTAssertTrue(viewData.showsPlaceholderHashrate)
        XCTAssertFalse(viewData.isReachable)
        XCTAssertFalse(viewData.isAccessible)
        XCTAssertFalse(viewData.showsLock)
    }

    func testMakeViewDataMarksPreviewMetricsAsReachable() {
        let viewData = DeviceListItemPresenter.makeViewData(
            device: SavedDevice(name: "Preview Miner", ipAddress: "192.168.1.13"),
            metrics: DeviceMetrics(hashrate: 500),
            index: 0,
            reachableIPs: [],
            isLoadingAggregatedStats: false,
            subscriptionAccessPolicy: SubscriptionAccessPolicy.accommodatingFallback,
            isPreview: true
        )

        XCTAssertTrue(viewData.isReachable)
    }

    private func makeLoadedFreePolicy() -> SubscriptionAccessPolicy {
        SubscriptionAccessPolicy(
            proIsActive: false,
            miners5IsActive: false,
            hasLoadedSubscription: true
        )
    }
}
