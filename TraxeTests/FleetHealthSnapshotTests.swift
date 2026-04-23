import XCTest

@testable import Traxe

final class FleetHealthSnapshotTests: XCTestCase {
    func testMakeCountsIndependentReportedSignals() {
        let devices = [
            SavedDevice(name: "Hashing", ipAddress: "192.168.1.10"),
            SavedDevice(name: "Hot", ipAddress: "192.168.1.11"),
            SavedDevice(name: "Paused No Hashrate", ipAddress: "192.168.1.12"),
            SavedDevice(name: "Unreachable", ipAddress: "192.168.1.13"),
        ]
        let metricsByIP = [
            "192.168.1.10": DeviceMetrics(hashrate: 720, temperature: 62),
            "192.168.1.11": DeviceMetrics(hashrate: 700, temperature: 82),
            "192.168.1.12": DeviceMetrics(
                hashrate: 0,
                temperature: 58,
                isMiningPaused: true
            ),
            "192.168.1.13": DeviceMetrics(hashrate: 640, temperature: 61),
        ]

        let snapshot = FleetHealthSnapshot.make(
            devices: devices,
            metricsByIP: metricsByIP,
            reachableIPs: Set(["192.168.1.10", "192.168.1.11", "192.168.1.12"]),
            isRefreshing: false
        )

        XCTAssertEqual(snapshot.totalMiners, 4)
        XCTAssertEqual(snapshot.online, 2)
        XCTAssertEqual(snapshot.paused, 1)
        XCTAssertEqual(snapshot.offline, 1)
        XCTAssertEqual(snapshot.unknown, 0)
        XCTAssertEqual(snapshot.zeroHashrate, 1)
        XCTAssertEqual(snapshot.highTemperature, 1)
    }

    func testMakeDoesNotTreatCachedMetricsAsReachableDuringRefresh() {
        let devices = [
            SavedDevice(name: "Cached", ipAddress: "192.168.1.20")
        ]
        let metricsByIP = [
            "192.168.1.20": DeviceMetrics(hashrate: 500, temperature: 60)
        ]

        let snapshot = FleetHealthSnapshot.make(
            devices: devices,
            metricsByIP: metricsByIP,
            reachableIPs: [],
            isRefreshing: true
        )

        XCTAssertEqual(snapshot.online, 0)
        XCTAssertEqual(snapshot.offline, 1)
        XCTAssertEqual(snapshot.unknown, 0)
        XCTAssertEqual(snapshot.zeroHashrate, 0)
        XCTAssertEqual(snapshot.highTemperature, 0)
    }

    func testMakeCountsRespondingMinerOnlineWhenMiningPausedFieldIsMissing() {
        let devices = [
            SavedDevice(name: "Fork", ipAddress: "192.168.1.30")
        ]
        let metricsByIP = [
            "192.168.1.30": DeviceMetrics(
                hashrate: 0,
                temperature: 0,
                isHashrateKnown: false,
                isTemperatureKnown: false,
                isMiningPaused: false,
                isMiningPausedKnown: false
            )
        ]

        let snapshot = FleetHealthSnapshot.make(
            devices: devices,
            metricsByIP: metricsByIP,
            reachableIPs: Set(["192.168.1.30"]),
            isRefreshing: false
        )

        XCTAssertEqual(snapshot.online, 1)
        XCTAssertEqual(snapshot.paused, 0)
        XCTAssertEqual(snapshot.offline, 0)
        XCTAssertEqual(snapshot.unknown, 0)
        XCTAssertEqual(snapshot.zeroHashrate, 0)
        XCTAssertEqual(snapshot.highTemperature, 0)
    }

    func testMakeMarksReachableMinerUnknownWhenMetricsAreMissing() {
        let devices = [
            SavedDevice(name: "Reachable", ipAddress: "192.168.1.35")
        ]

        let snapshot = FleetHealthSnapshot.make(
            devices: devices,
            metricsByIP: [:],
            reachableIPs: Set(["192.168.1.35"]),
            isRefreshing: false
        )

        XCTAssertEqual(snapshot.online, 0)
        XCTAssertEqual(snapshot.paused, 0)
        XCTAssertEqual(snapshot.offline, 0)
        XCTAssertEqual(snapshot.unknown, 1)
        XCTAssertEqual(snapshot.zeroHashrate, 0)
        XCTAssertEqual(snapshot.highTemperature, 0)
    }

    func testMakeStillCountsKnownSignalsWhenOtherPrimaryFieldsAreMissing() {
        let devices = [
            SavedDevice(name: "Zero Hashrate", ipAddress: "192.168.1.40"),
            SavedDevice(name: "Hot", ipAddress: "192.168.1.41"),
        ]
        let metricsByIP = [
            "192.168.1.40": DeviceMetrics(
                hashrate: 0,
                temperature: 0,
                isHashrateKnown: true,
                isTemperatureKnown: false
            ),
            "192.168.1.41": DeviceMetrics(
                hashrate: 0,
                temperature: 90,
                isHashrateKnown: false,
                isTemperatureKnown: true
            ),
        ]

        let snapshot = FleetHealthSnapshot.make(
            devices: devices,
            metricsByIP: metricsByIP,
            reachableIPs: Set(["192.168.1.40", "192.168.1.41"]),
            isRefreshing: false
        )

        XCTAssertEqual(snapshot.online, 2)
        XCTAssertEqual(snapshot.highTemperature, 1)
        XCTAssertEqual(snapshot.zeroHashrate, 1)
    }
}
