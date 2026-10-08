import Foundation
import XCTest

@testable import Traxe

final class FleetSummarySnapshotTests: XCTestCase {
    func testSummaryUsesReportingSubsetForHashratePowerAndTemperatures() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshot = FleetMetricSnapshot.make(
            readings: [
                .init(id: "a", hashrate: 400, power: 12, measuredAt: now, isReachable: true),
                .init(id: "b", hashrate: 600, power: 18, measuredAt: now, isReachable: false),
            ],
            totalDevices: 2,
            referenceDate: now
        )
        let summary = AISummaryFormatter.fleetSummary(
            from: [
                "a": DeviceMetrics(hashrate: 400, temperature: 55, power: 12),
                "b": DeviceMetrics(hashrate: 600, temperature: 99, power: 18),
            ],
            snapshot: snapshot
        )
        XCTAssertTrue(summary.content.contains("1 of 2 miners reporting"))
        XCTAssertTrue(summary.content.contains("400.0 GH/s"))
        XCTAssertTrue(summary.content.contains("12W"))
        XCTAssertFalse(summary.content.contains("99"))
        XCTAssertFalse(summary.content.contains("30W"))
        XCTAssertFalse(summary.content.contains("above 75°C"))
    }

    func testSummaryQualifiesLastKnownTotalWhenNoMinersRespond() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshot = FleetMetricSnapshot.make(
            readings: [
                .init(id: "a", hashrate: 400, measuredAt: now, isReachable: false),
                .init(id: "b", hashrate: 600, measuredAt: now, isReachable: false),
            ],
            totalDevices: 2,
            referenceDate: now
        )
        let summary = AISummaryFormatter.fleetSummary(
            from: ["a": DeviceMetrics(hashrate: 400), "b": DeviceMetrics(hashrate: 600)],
            snapshot: snapshot
        )
        XCTAssertTrue(summary.content.contains("Last known · stale"))
        XCTAssertTrue(summary.content.contains("1.0 TH/s"))
    }

    func testSummaryWithoutMeasurementsDoesNotDescribeZeroProduction() {
        let snapshot = FleetMetricSnapshot.make(readings: [], totalDevices: 2)
        let summary = AISummaryFormatter.fleetSummary(from: [:], snapshot: snapshot)
        XCTAssertEqual(summary.content, "No readings yet.")
        XCTAssertFalse(summary.content.contains("0"))
    }

    func testSingleAndEqualTemperaturesUseOneDisplayedValue() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        for temperatures in [[55.0], [55.0, 55.0], [55.1, 55.2]] {
            var metrics: [String: DeviceMetrics] = [:]
            var readings: [FleetMetricSnapshot.Reading] = []
            for (index, temperature) in temperatures.enumerated() {
                let id = "miner-\(index)"
                metrics[id] = DeviceMetrics(hashrate: 400, temperature: temperature, power: 12)
                readings.append(.init(id: id, hashrate: 400, measuredAt: now, isReachable: true))
            }
            let snapshot = FleetMetricSnapshot.make(
                readings: readings,
                totalDevices: temperatures.count,
                referenceDate: now
            )

            let summary = AISummaryFormatter.fleetSummary(from: metrics, snapshot: snapshot)

            XCTAssertTrue(summary.content.contains("temperature 55°C"))
            XCTAssertFalse(summary.content.contains("55–55"))
        }
    }

    func testHotWarningCountsOnlyKnownTemperaturesFromIncludedMiners() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshot = FleetMetricSnapshot.make(
            readings: [
                .init(id: "threshold", hashrate: 400, measuredAt: now, isReachable: true),
                .init(id: "hot", hashrate: 400, measuredAt: now, isReachable: true),
                .init(id: "unknown", hashrate: 400, measuredAt: now, isReachable: true),
                .init(id: "unreachable", hashrate: 400, measuredAt: now, isReachable: false),
            ],
            totalDevices: 4,
            referenceDate: now
        )
        let summary = AISummaryFormatter.fleetSummary(
            from: [
                "threshold": DeviceMetrics(hashrate: 400, temperature: 75),
                "hot": DeviceMetrics(hashrate: 400, temperature: 80),
                "unknown": DeviceMetrics(hashrate: 400, temperature: 99, isTemperatureKnown: false),
                "unreachable": DeviceMetrics(hashrate: 400, temperature: 95),
            ],
            snapshot: snapshot
        )

        XCTAssertTrue(summary.content.contains("temperatures 75–80°C"))
        XCTAssertTrue(summary.content.contains("(1 above 75°C)"))
        XCTAssertFalse(summary.content.contains("99"))
        XCTAssertFalse(summary.content.contains("95"))
    }

    func testStaleHotWarningUsesTheSameLastKnownIncludedMiners() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshot = FleetMetricSnapshot.make(
            readings: [.init(id: "hot", hashrate: 400, measuredAt: now, isReachable: false)],
            totalDevices: 1,
            referenceDate: now
        )
        let summary = AISummaryFormatter.fleetSummary(
            from: ["hot": DeviceMetrics(hashrate: 400, temperature: 80)],
            snapshot: snapshot
        )

        XCTAssertTrue(summary.content.contains("Last known · stale"))
        XCTAssertTrue(summary.content.contains("temperature 80°C"))
        XCTAssertTrue(summary.content.contains("(1 above 75°C)"))
    }

}
