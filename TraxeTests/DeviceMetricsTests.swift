import XCTest

@testable import Traxe

final class DeviceMetricsTests: XCTestCase {
    func testDifficultyConversionKeepsBothTelemetryPathsFinite() throws {
        let cases: [(String, Double)] = [
            ("nan", 0),
            ("inf", 0),
            ("-inf", 0),
            ("1e999", 0),
            ("1e308P", 0),
            ("1e308G", 0),
            ("-5 M", 0),
            ("0", 0),
            ("0 M", 0),
            ("1,250 K", 1.25),
            ("598.7M", 598.7),
            ("2.3g", 2_300),
            ("4,070 T", 4_070_000_000),
            ("1 P", 1_000_000_000),
            ("5000000", 5),
            ("5000000.", 5),
            ("1e308M", 1e308),
        ]
        for (value, expected) in cases {
            let data = try JSONEncoder().encode(["bestDiff": value])
            let telemetry = try JSONDecoder().decode(MinerTelemetryDTO.self, from: data)
            let systemInfo = try JSONDecoder().decode(SystemInfoDTO.self, from: data)
            XCTAssertEqual(DeviceMetrics(from: telemetry).bestDifficulty, expected, value)
            XCTAssertEqual(DeviceMetrics(from: systemInfo).bestDifficulty, expected, value)
        }
    }

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
