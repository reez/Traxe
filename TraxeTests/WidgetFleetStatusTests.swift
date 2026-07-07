import XCTest

@testable import Traxe

final class WidgetFleetStatusTests: XCTestCase {
    func testMakeMatchesFleetHealthStateSemantics() {
        let status = WidgetFleetStatus.make(
            deviceIDs: ["online", "paused", "offline", "unknown"],
            respondedDeviceIDs: Set(["online", "paused", "unknown"]),
            deviceIDsWithMetrics: Set(["online", "paused"]),
            pausedDeviceIDs: Set(["paused"])
        )

        XCTAssertEqual(
            status,
            WidgetFleetStatus(total: 4, online: 1, paused: 1, offline: 1, unknown: 1)
        )
    }

    func testMakeTreatsRespondingMinerWithoutKnownPausedStateAsOnline() {
        let status = WidgetFleetStatus.make(
            deviceIDs: ["miner"],
            respondedDeviceIDs: Set(["miner"]),
            deviceIDsWithMetrics: Set(["miner"]),
            pausedDeviceIDs: []
        )

        XCTAssertEqual(
            status,
            WidgetFleetStatus(total: 1, online: 1, paused: 0, offline: 0, unknown: 0)
        )
    }
}
