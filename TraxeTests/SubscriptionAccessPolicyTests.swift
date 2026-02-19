import XCTest

@testable import Traxe

final class SubscriptionAccessPolicyTests: XCTestCase {
    func testAccommodatingFallbackAllowsAllDevices() {
        let policy = SubscriptionAccessPolicy.accommodatingFallback
        let devices = makeDevices(count: 6)

        XCTAssertEqual(policy.deviceLimit, Int.max)
        XCTAssertEqual(policy.accessibleDevices(from: devices).count, 6)
        XCTAssertFalse(policy.shouldShowLocks)
    }

    func testFreeTierLimitsAccessToFirstDevice() {
        let policy = SubscriptionAccessPolicy(
            proIsActive: false,
            miners5IsActive: false,
            hasLoadedSubscription: true
        )
        let devices = makeDevices(count: 6)

        XCTAssertEqual(policy.deviceLimit, 1)
        XCTAssertEqual(policy.accessibleDevices(from: devices).count, 1)
        XCTAssertTrue(policy.isDeviceAccessible(at: 0))
        XCTAssertFalse(policy.isDeviceAccessible(at: 1))
        XCTAssertTrue(policy.shouldShowSubscriptionExpiredAlert)
    }

    func testMinersFiveTierLimitsAccessToFirstFiveDevices() {
        let policy = SubscriptionAccessPolicy(
            proIsActive: false,
            miners5IsActive: true,
            hasLoadedSubscription: true
        )
        let devices = makeDevices(count: 6)

        XCTAssertEqual(policy.deviceLimit, 5)
        XCTAssertEqual(policy.accessibleDevices(from: devices).count, 5)
        XCTAssertTrue(policy.isDeviceAccessible(at: 4))
        XCTAssertFalse(policy.isDeviceAccessible(at: 5))
        XCTAssertFalse(policy.shouldShowSubscriptionExpiredAlert)
    }

    func testProTierAllowsAllDevices() {
        let policy = SubscriptionAccessPolicy(
            proIsActive: true,
            miners5IsActive: false,
            hasLoadedSubscription: true
        )
        let devices = makeDevices(count: 8)

        XCTAssertEqual(policy.deviceLimit, Int.max)
        XCTAssertEqual(policy.accessibleDevices(from: devices).count, 8)
        XCTAssertTrue(policy.isDeviceAccessible(at: 7))
        XCTAssertFalse(policy.shouldShowSubscriptionExpiredAlert)
    }

    private func makeDevices(count: Int) -> [SavedDevice] {
        (1...count).map { index in
            SavedDevice(name: "Miner \(index)", ipAddress: "192.168.1.\(index)")
        }
    }
}
