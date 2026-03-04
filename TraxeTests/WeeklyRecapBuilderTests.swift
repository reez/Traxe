import Foundation
import XCTest

@testable import Traxe

final class WeeklyRecapBuilderTests: XCTestCase {
    func testBuildReturnsNilWhenNoSamplesInRange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let now = makeDate(year: 2026, month: 3, day: 1, hour: 12, calendar: calendar)

        let recap = WeeklyRecapBuilder.build(
            from: [HistoricalDataPoint](),
            now: now,
            calendar: calendar
        )

        XCTAssertNil(recap)
    }

    func testBuildProducesSevenDailyPointsAndTrend() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let now = makeDate(year: 2026, month: 3, day: 1, hour: 12, calendar: calendar)

        let day1 = makeDate(year: 2026, month: 2, day: 24, hour: 10, calendar: calendar)
        let day2 = makeDate(year: 2026, month: 2, day: 26, hour: 10, calendar: calendar)
        let day3 = makeDate(year: 2026, month: 3, day: 1, hour: 10, calendar: calendar)

        let points = [
            HistoricalDataPoint(timestamp: day1, hashrate: 100, temperature: 60, deviceId: "miner"),
            HistoricalDataPoint(timestamp: day2, hashrate: 150, temperature: 62, deviceId: "miner"),
            HistoricalDataPoint(timestamp: day3, hashrate: 200, temperature: 64, deviceId: "miner"),
        ]

        let recap = WeeklyRecapBuilder.build(from: points, now: now, calendar: calendar)

        XCTAssertNotNil(recap)
        XCTAssertEqual(recap?.dailyPoints.count, 7)
        XCTAssertEqual(recap?.activeDays, 3)
        XCTAssertEqual(recap?.averageHashrate ?? 0, 150, accuracy: 0.001)
        XCTAssertEqual(recap?.peakHashrate ?? 0, 200, accuracy: 0.001)
        XCTAssertEqual(recap?.hashrateChangePercent ?? 0, 100, accuracy: 0.001)
    }

    func testBuildIgnoresSamplesOlderThanSevenDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let now = makeDate(year: 2026, month: 3, day: 1, hour: 12, calendar: calendar)

        let oldSample = makeDate(year: 2026, month: 2, day: 20, hour: 9, calendar: calendar)
        let inRangeSample = makeDate(year: 2026, month: 2, day: 28, hour: 9, calendar: calendar)

        let points = [
            HistoricalDataPoint(
                timestamp: oldSample,
                hashrate: 900,
                temperature: 80,
                deviceId: "miner"
            ),
            HistoricalDataPoint(
                timestamp: inRangeSample,
                hashrate: 120,
                temperature: 61,
                deviceId: "miner"
            ),
        ]

        let recap = WeeklyRecapBuilder.build(from: points, now: now, calendar: calendar)

        XCTAssertNotNil(recap)
        XCTAssertEqual(recap?.sampleCount, 1)
        XCTAssertEqual(recap?.averageHashrate ?? 0, 120, accuracy: 0.001)
        XCTAssertEqual(recap?.maxTemperature ?? 0, 61, accuracy: 0.001)
    }

    func testBuildIgnoresZeroTemperatureSamplesForTemperatureStats() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let now = makeDate(year: 2026, month: 3, day: 1, hour: 12, calendar: calendar)

        let day1 = makeDate(year: 2026, month: 2, day: 27, hour: 10, calendar: calendar)
        let day2 = makeDate(year: 2026, month: 2, day: 28, hour: 10, calendar: calendar)
        let day3 = makeDate(year: 2026, month: 3, day: 1, hour: 10, calendar: calendar)

        let points = [
            HistoricalDataPoint(timestamp: day1, hashrate: 100, temperature: 0, deviceId: "miner"),
            HistoricalDataPoint(timestamp: day1, hashrate: 102, temperature: 61, deviceId: "miner"),
            HistoricalDataPoint(timestamp: day2, hashrate: 98, temperature: 0, deviceId: "miner"),
            HistoricalDataPoint(timestamp: day2, hashrate: 101, temperature: 63, deviceId: "miner"),
            HistoricalDataPoint(timestamp: day3, hashrate: 99, temperature: 62, deviceId: "miner"),
        ]

        let recap = WeeklyRecapBuilder.build(from: points, now: now, calendar: calendar)

        XCTAssertNotNil(recap)
        XCTAssertEqual(recap?.averageTemperature ?? 0, 62, accuracy: 0.001)
        XCTAssertEqual(recap?.minTemperature ?? 0, 61, accuracy: 0.001)
        XCTAssertEqual(recap?.maxTemperature ?? 0, 63, accuracy: 0.001)
    }

    func testPoolAllocationBuilderUsesFullHashrateForSinglePool() {
        let allocations = WeeklyRecapPoolAllocationBuilder.build(
            from: "mine.ocean.xyz",
            totalHashrate: 13_400
        )

        XCTAssertEqual(allocations.count, 1)
        XCTAssertEqual(allocations.first?.name, "Ocean")
        XCTAssertEqual(allocations.first?.logoName, "ocean")
        XCTAssertEqual(allocations.first?.estimatedHashrate ?? 0, 13_400, accuracy: 0.001)
    }

    func testPoolAllocationBuilderSplitsDualPoolHashrateByPercent() {
        let allocations = WeeklyRecapPoolAllocationBuilder.build(
            from: "mine.ocean.xyz (65%) • publicpool.io (35%)",
            totalHashrate: 20_600
        )

        XCTAssertEqual(allocations.count, 2)
        XCTAssertEqual(allocations[0].name, "Ocean")
        XCTAssertEqual(allocations[0].configuredPercent ?? 0, 65, accuracy: 0.001)
        XCTAssertEqual(allocations[0].estimatedHashrate, 13_390, accuracy: 0.001)
        XCTAssertEqual(allocations[1].name, "Public Pool")
        XCTAssertEqual(allocations[1].configuredPercent ?? 0, 35, accuracy: 0.001)
        XCTAssertEqual(allocations[1].estimatedHashrate, 7_210, accuracy: 0.001)
    }

    func testPoolAllocationBuilderAggregatesFleetTotalsAcrossDevices() {
        let allocations = WeeklyRecapPoolAllocationBuilder.buildFleetTotals(
            from: [
                (
                    poolDisplayName: "mine.ocean.xyz (65%) • publicpool.io (35%)",
                    totalHashrate: 20_600
                ),
                (poolDisplayName: "mine.ocean.xyz", totalHashrate: 720),
            ]
        )

        XCTAssertEqual(allocations.count, 2)
        XCTAssertEqual(allocations[0].name, "Ocean")
        XCTAssertEqual(allocations[0].estimatedHashrate, 14_110, accuracy: 0.001)
        XCTAssertEqual(allocations[1].name, "Public Pool")
        XCTAssertEqual(allocations[1].estimatedHashrate, 7_210, accuracy: 0.001)
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        calendar: Calendar
    ) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = 0
        components.second = 0
        return components.date ?? Date()
    }
}
