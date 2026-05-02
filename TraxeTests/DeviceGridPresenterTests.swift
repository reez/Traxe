import XCTest

@testable import Traxe

final class DeviceGridPresenterTests: XCTestCase {
    func testMakeItemsPreservesSavedOrderWithoutRanksOutsideScoreboard() {
        let items = DeviceGridPresenter.makeItems(
            devices: makeDevices(),
            metricsByIP: makeMetrics(),
            sortOption: .savedOrder
        )

        XCTAssertEqual(
            items.map(\.id),
            ["192.168.1.10", "192.168.1.11", "192.168.1.12", "192.168.1.13"]
        )
        XCTAssertEqual(items.map(\.savedDeviceIndex), [0, 1, 2, 3])
        XCTAssertEqual(items.map(\.bestDifficultyRank), [nil, nil, nil, nil])
    }

    func testMakeItemsSortsScoreboardByBestDifficultyAndKeepsInvalidValuesAtEnd() {
        let items = DeviceGridPresenter.makeItems(
            devices: makeDevices(),
            metricsByIP: makeMetrics(),
            sortOption: .scoreboard
        )

        XCTAssertEqual(
            items.map(\.id),
            ["192.168.1.11", "192.168.1.13", "192.168.1.10", "192.168.1.12"]
        )
        XCTAssertEqual(items.map(\.bestDifficultyRank), [1, 2, 3, nil])
    }

    func testMakeItemsSortsByHashrateWithoutChangingSavedDeviceIndex() {
        let items = DeviceGridPresenter.makeItems(
            devices: makeDevices(),
            metricsByIP: makeMetrics(),
            sortOption: .hashrate
        )

        XCTAssertEqual(
            items.map(\.id),
            ["192.168.1.11", "192.168.1.13", "192.168.1.10", "192.168.1.12"]
        )
        XCTAssertEqual(items.map(\.savedDeviceIndex), [1, 3, 0, 2])
        XCTAssertEqual(items.map(\.bestDifficultyRank), [nil, nil, nil, nil])
    }

    func testMakeItemsPreservesSavedOrderForSortTies() {
        let devices = [
            SavedDevice(name: "First", ipAddress: "192.168.1.20"),
            SavedDevice(name: "Second", ipAddress: "192.168.1.21"),
            SavedDevice(name: "Third", ipAddress: "192.168.1.22"),
        ]
        let metricsByIP = [
            "192.168.1.20": DeviceMetrics(hashrate: 700, bestDifficulty: 10),
            "192.168.1.21": DeviceMetrics(hashrate: 800, bestDifficulty: 10),
            "192.168.1.22": DeviceMetrics(hashrate: 900, bestDifficulty: 9),
        ]

        let items = DeviceGridPresenter.makeItems(
            devices: devices,
            metricsByIP: metricsByIP,
            sortOption: .scoreboard
        )

        XCTAssertEqual(items.map(\.id), ["192.168.1.20", "192.168.1.21", "192.168.1.22"])
        XCTAssertEqual(items.map(\.bestDifficultyRank), [1, 2, 3])
    }

    func testMakeItemsRanksEveryMinerWithValidBestDifficultyInScoreboard() {
        let devices = [
            SavedDevice(name: "First", ipAddress: "192.168.1.30"),
            SavedDevice(name: "Second", ipAddress: "192.168.1.31"),
            SavedDevice(name: "Third", ipAddress: "192.168.1.32"),
            SavedDevice(name: "Fourth", ipAddress: "192.168.1.33"),
        ]
        let metricsByIP = [
            "192.168.1.30": DeviceMetrics(hashrate: 700, bestDifficulty: 10),
            "192.168.1.31": DeviceMetrics(hashrate: 800, bestDifficulty: 40),
            "192.168.1.32": DeviceMetrics(hashrate: 900, bestDifficulty: 20),
            "192.168.1.33": DeviceMetrics(hashrate: 1_000, bestDifficulty: 30),
        ]

        let items = DeviceGridPresenter.makeItems(
            devices: devices,
            metricsByIP: metricsByIP,
            sortOption: .scoreboard
        )

        XCTAssertEqual(
            items.map(\.id),
            ["192.168.1.31", "192.168.1.33", "192.168.1.32", "192.168.1.30"]
        )
        XCTAssertEqual(items.map(\.bestDifficultyRank), [1, 2, 3, 4])
    }

    private func makeDevices() -> [SavedDevice] {
        [
            SavedDevice(name: "Garage", ipAddress: "192.168.1.10"),
            SavedDevice(name: "Office", ipAddress: "192.168.1.11"),
            SavedDevice(name: "Kitchen", ipAddress: "192.168.1.12"),
            SavedDevice(name: "Closet", ipAddress: "192.168.1.13"),
        ]
    }

    private func makeMetrics() -> [String: DeviceMetrics] {
        [
            "192.168.1.10": DeviceMetrics(
                hashrate: 700,
                bestDifficulty: 598.7,
                hostname: "bitaxe"
            ),
            "192.168.1.11": DeviceMetrics(
                hashrate: 5_100,
                bestDifficulty: 4_070,
                hostname: "nerdqaxe++"
            ),
            "192.168.1.12": DeviceMetrics(
                hashrate: 450,
                bestDifficulty: 0
            ),
            "192.168.1.13": DeviceMetrics(
                hashrate: 3_800,
                bestDifficulty: 1_200
            ),
        ]
    }
}
