import Foundation
import SwiftData
import XCTest

@testable import Traxe

@MainActor
final class HistoricalDataRetentionControllerTests: XCTestCase {
    func testSavePendingChangesPrunesStaleRowsOnFirstSave() throws {
        let modelContainer = try makeInMemoryModelContainer()
        let modelContext = modelContainer.mainContext
        let clock = MutableClock(
            now: makeDate(year: 2026, month: 3, day: 20, hour: 12)
        )
        let controller = HistoricalDataRetentionController(
            modelContext: modelContext,
            retentionInterval: 60 * 60 * 24 * 30,
            pruneInterval: 60 * 60,
            now: { clock.now }
        )

        modelContext.insert(
            HistoricalDataPoint(
                timestamp: clock.now.addingTimeInterval(-(60 * 60 * 24 * 31)),
                hashrate: 100,
                temperature: 60,
                deviceId: "miner-a"
            )
        )
        try modelContext.save()

        modelContext.insert(
            HistoricalDataPoint(
                timestamp: clock.now,
                hashrate: 200,
                temperature: 61,
                deviceId: "miner-a"
            )
        )

        try controller.savePendingChanges(pruningIfNeededFor: "miner-a")

        let rows = try fetchRows(for: "miner-a", in: modelContext)
        XCTAssertEqual(rows.map(\.hashrate), [200])
    }

    func testSavePendingChangesSkipsPruneWithinThrottleInterval() throws {
        let modelContainer = try makeInMemoryModelContainer()
        let modelContext = modelContainer.mainContext
        let clock = MutableClock(
            now: makeDate(year: 2026, month: 3, day: 20, hour: 12)
        )
        let controller = HistoricalDataRetentionController(
            modelContext: modelContext,
            retentionInterval: 60 * 60 * 24 * 30,
            pruneInterval: 60 * 60,
            now: { clock.now }
        )

        modelContext.insert(
            HistoricalDataPoint(
                timestamp: clock.now,
                hashrate: 200,
                temperature: 61,
                deviceId: "miner-a"
            )
        )
        try controller.savePendingChanges(pruningIfNeededFor: "miner-a")

        clock.advance(by: 60 * 30)

        modelContext.insert(
            HistoricalDataPoint(
                timestamp: clock.now.addingTimeInterval(-(60 * 60 * 24 * 31)),
                hashrate: 50,
                temperature: 58,
                deviceId: "miner-a"
            )
        )
        try modelContext.save()
        modelContext.insert(
            HistoricalDataPoint(
                timestamp: clock.now,
                hashrate: 250,
                temperature: 62,
                deviceId: "miner-a"
            )
        )

        try controller.savePendingChanges(pruningIfNeededFor: "miner-a")

        let rows = try fetchRows(for: "miner-a", in: modelContext)
        XCTAssertEqual(rows.map(\.hashrate), [50, 200, 250])
    }

    func testSavePendingChangesPrunesAgainAfterThrottleInterval() throws {
        let modelContainer = try makeInMemoryModelContainer()
        let modelContext = modelContainer.mainContext
        let clock = MutableClock(
            now: makeDate(year: 2026, month: 3, day: 20, hour: 12)
        )
        let controller = HistoricalDataRetentionController(
            modelContext: modelContext,
            retentionInterval: 60 * 60 * 24 * 30,
            pruneInterval: 60 * 60,
            now: { clock.now }
        )

        modelContext.insert(
            HistoricalDataPoint(
                timestamp: clock.now,
                hashrate: 200,
                temperature: 61,
                deviceId: "miner-a"
            )
        )
        try controller.savePendingChanges(pruningIfNeededFor: "miner-a")

        clock.advance(by: (60 * 60) + 1)

        modelContext.insert(
            HistoricalDataPoint(
                timestamp: clock.now.addingTimeInterval(-(60 * 60 * 24 * 31)),
                hashrate: 50,
                temperature: 58,
                deviceId: "miner-a"
            )
        )
        try modelContext.save()
        modelContext.insert(
            HistoricalDataPoint(
                timestamp: clock.now,
                hashrate: 250,
                temperature: 62,
                deviceId: "miner-a"
            )
        )

        try controller.savePendingChanges(pruningIfNeededFor: "miner-a")

        let rows = try fetchRows(for: "miner-a", in: modelContext)
        XCTAssertEqual(rows.map(\.hashrate), [200, 250])
    }

    func testSavePendingChangesBatchThrottlesPerDeviceIndependently() throws {
        let modelContainer = try makeInMemoryModelContainer()
        let modelContext = modelContainer.mainContext
        let clock = MutableClock(
            now: makeDate(year: 2026, month: 3, day: 20, hour: 12)
        )
        let controller = HistoricalDataRetentionController(
            modelContext: modelContext,
            retentionInterval: 60 * 60 * 24 * 30,
            pruneInterval: 60 * 60,
            now: { clock.now }
        )

        modelContext.insert(
            HistoricalDataPoint(
                timestamp: clock.now,
                hashrate: 100,
                temperature: 60,
                deviceId: "miner-a"
            )
        )
        try controller.savePendingChanges(pruningIfNeededFor: "miner-a")

        clock.advance(by: 60 * 30)

        modelContext.insert(
            HistoricalDataPoint(
                timestamp: clock.now,
                hashrate: 200,
                temperature: 61,
                deviceId: "miner-b"
            )
        )
        try controller.savePendingChanges(pruningIfNeededFor: "miner-b")

        clock.advance(by: (60 * 31) + 1)

        modelContext.insert(
            HistoricalDataPoint(
                timestamp: clock.now.addingTimeInterval(-(60 * 60 * 24 * 31)),
                hashrate: 50,
                temperature: 58,
                deviceId: "miner-a"
            )
        )
        modelContext.insert(
            HistoricalDataPoint(
                timestamp: clock.now.addingTimeInterval(-(60 * 60 * 24 * 31)),
                hashrate: 75,
                temperature: 57,
                deviceId: "miner-b"
            )
        )
        try modelContext.save()

        modelContext.insert(
            HistoricalDataPoint(
                timestamp: clock.now,
                hashrate: 110,
                temperature: 62,
                deviceId: "miner-a"
            )
        )
        modelContext.insert(
            HistoricalDataPoint(
                timestamp: clock.now,
                hashrate: 210,
                temperature: 63,
                deviceId: "miner-b"
            )
        )

        try controller.savePendingChanges(
            pruningIfNeededFor: ["miner-a", "miner-b", "miner-a"]
        )

        let minerARows = try fetchRows(for: "miner-a", in: modelContext)
        XCTAssertEqual(minerARows.map(\.hashrate), [100, 110])

        let minerBRows = try fetchRows(for: "miner-b", in: modelContext)
        XCTAssertEqual(minerBRows.map(\.hashrate), [75, 200, 210])
    }

    private func makeInMemoryModelContainer() throws -> ModelContainer {
        let schema = Schema([HistoricalDataPoint.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func fetchRows(
        for deviceId: String,
        in modelContext: ModelContext
    ) throws -> [HistoricalDataPoint] {
        let descriptor = FetchDescriptor<HistoricalDataPoint>(
            predicate: #Predicate<HistoricalDataPoint> { data in
                data.deviceId == deviceId
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

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

private final class MutableClock: @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}
