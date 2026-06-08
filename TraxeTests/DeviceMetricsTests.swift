import XCTest

@testable import Traxe

final class DeviceMetricsTests: XCTestCase {
    func testEfficiencyIsZeroWhenHashrateIsZero() {
        let metrics = DeviceMetrics(hashrate: 0, power: 100)

        XCTAssertEqual(metrics.efficiency, 0, accuracy: 0.001)
    }

    func testEfficiencyIsZeroWhenHashrateRoundsToZeroMegahash() {
        let metrics = DeviceMetrics(hashrate: 0.0004, power: 100)
        let formattedHashrate = metrics.hashrate.formattedHashRateWithUnit()

        XCTAssertEqual(formattedHashrate.value, "0")
        XCTAssertEqual(formattedHashrate.unit, "MH/s")
        XCTAssertEqual(metrics.efficiency, 0, accuracy: 0.001)
    }

    func testEfficiencyUsesWattsPerTerahashForNormalHashrate() {
        let metrics = DeviceMetrics(hashrate: 5_000, power: 100)

        XCTAssertEqual(metrics.efficiency, 20, accuracy: 0.001)
    }
}
