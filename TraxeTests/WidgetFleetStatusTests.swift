import XCTest

@testable import Traxe

final class WidgetFleetStatusTests: XCTestCase {
    func testZeroHashrateAlertOverlapsOnlineAndPausedButExcludesUnreachableAndUnknown() {
        let status = WidgetFleetStatus.make(
            deviceIDs: ["online-zero", "paused-zero", "hashing", "offline", "unknown"],
            respondedDeviceIDs: ["online-zero", "paused-zero", "hashing", "unknown"],
            deviceIDsWithMetrics: ["online-zero", "paused-zero", "hashing", "offline"],
            pausedDeviceIDs: ["paused-zero"],
            knownHashratesByDeviceID: [
                "online-zero": 0, "paused-zero": 0, "hashing": 1_000,
                "offline": 0, "unknown": 0, "removed": 0,
            ]
        )

        XCTAssertEqual(
            status,
            WidgetFleetStatus(
                total: 5, online: 2, paused: 1, offline: 1, unknown: 1, zeroHashrate: 2
            )
        )
    }

    func testZeroHashrateAlertDoesNotTreatMissingOrInvalidHashrateAsZero() {
        let status = WidgetFleetStatus.make(
            deviceIDs: ["missing", "negative", "nan", "infinite", "hashing"],
            respondedDeviceIDs: ["missing", "negative", "nan", "infinite", "hashing"],
            deviceIDsWithMetrics: ["missing", "negative", "nan", "infinite", "hashing"],
            pausedDeviceIDs: [],
            knownHashratesByDeviceID: [
                "negative": -1, "nan": .nan, "infinite": .infinity, "hashing": 1,
            ]
        )

        XCTAssertEqual(status.zeroHashrate, 0)
        XCTAssertEqual(status.online, 5)
    }

    func testZeroHashrateAlertUsesOnlyCurrentReportingReadings() {
        let now = Date()
        let readings: [FleetMetricSnapshot.Reading] = [
            .init(id: "zero", hashrate: 0, measuredAt: now, isReachable: true),
            .init(id: "unavailable", hashrate: nil, measuredAt: now, isReachable: true),
            .init(
                id: "cached-zero", hashrate: 0, measuredAt: now, isReachable: true,
                isHashrateReporting: false
            ),
            .init(id: "offline-zero", hashrate: 0, measuredAt: now, isReachable: false),
            .init(
                id: "stale-zero", hashrate: 0,
                measuredAt: now.addingTimeInterval(-3_600), isReachable: true
            ),
        ]
        let snapshot = FleetMetricSnapshot.make(
            readings: readings, totalDevices: readings.count, referenceDate: now
        )
        let status = WidgetFleetStatus.make(
            deviceIDs: readings.map(\.id),
            respondedDeviceIDs: snapshot.reportingDeviceIDs,
            deviceIDsWithMetrics: snapshot.includedDeviceIDs,
            pausedDeviceIDs: [],
            knownHashratesByDeviceID: Dictionary(
                uniqueKeysWithValues: readings.compactMap { reading in
                    reading.hashrate.map { (reading.id, $0) }
                }
            )
        )

        XCTAssertEqual(status.zeroHashrate, 1)
        XCTAssertEqual(status.online, 1)
        XCTAssertEqual(status.unknown, 2)
        XCTAssertEqual(status.offline, 2)
    }

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
