import Foundation
import SwiftData
import XCTest

@testable import Traxe

@MainActor
final class HistoricalDataRelocatorTests: XCTestCase {
    func testRelocateRewritesEveryPointForPreviousAddressAndLeavesOthersAlone() async throws {
        let schema = Schema([HistoricalDataPoint.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        let seedingContext = ModelContext(modelContainer)
        // More points than two relocation batches, so the batching loop is exercised.
        for index in 0..<1_203 {
            seedingContext.insert(
                HistoricalDataPoint(
                    timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                    hashrate: 1,
                    temperature: 50,
                    deviceId: "192.168.1.10"
                )
            )
        }
        seedingContext.insert(
            HistoricalDataPoint(hashrate: 2, temperature: 51, deviceId: "192.168.1.11")
        )
        try seedingContext.save()

        let relocator = HistoricalDataRelocator(modelContainer: modelContainer)
        try await relocator.relocate(
            ["192.168.1.10": "192.168.1.20"],
            before: .distantFuture,
            operationID: UUID().uuidString
        )

        let verifyingContext = ModelContext(modelContainer)
        let movedDeviceId: String? = "192.168.1.20"
        let previousDeviceId: String? = "192.168.1.10"
        let untouchedDeviceId: String? = "192.168.1.11"
        let moved = try verifyingContext.fetch(
            FetchDescriptor<HistoricalDataPoint>(
                predicate: #Predicate { $0.deviceId == movedDeviceId }
            )
        )
        let remaining = try verifyingContext.fetch(
            FetchDescriptor<HistoricalDataPoint>(
                predicate: #Predicate { $0.deviceId == previousDeviceId }
            )
        )
        let untouched = try verifyingContext.fetch(
            FetchDescriptor<HistoricalDataPoint>(
                predicate: #Predicate { $0.deviceId == untouchedDeviceId }
            )
        )
        XCTAssertEqual(moved.count, 1_203)
        XCTAssertEqual(remaining.count, 0)
        XCTAssertEqual(untouched.count, 1)
    }

    func testRelocateSwappedAddressesKeepsEachMinersHistorySeparateAcrossBatches() async throws {
        let schema = Schema([HistoricalDataPoint.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        let seedingContext = ModelContext(modelContainer)
        for index in 0..<1_203 {
            seedingContext.insert(
                HistoricalDataPoint(
                    timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                    hashrate: 1,
                    temperature: 50,
                    deviceId: "192.168.1.10"
                )
            )
        }
        for index in 0..<1_007 {
            seedingContext.insert(
                HistoricalDataPoint(
                    timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                    hashrate: 2,
                    temperature: 51,
                    deviceId: "192.168.1.11"
                )
            )
        }
        try seedingContext.save()

        let relocator = HistoricalDataRelocator(modelContainer: modelContainer)
        let moves = ["192.168.1.10": "192.168.1.11", "192.168.1.11": "192.168.1.10"]
        let operationID = UUID().uuidString
        try await relocator.relocate(
            moves,
            before: Date(timeIntervalSince1970: 2_000),
            operationID: operationID
        )
        // Replaying a saved operation after a crash must not swap the points back.
        try await relocator.relocate(
            moves,
            before: Date(timeIntervalSince1970: 2_000),
            operationID: operationID
        )

        let verifyingContext = ModelContext(modelContainer)
        let points = try verifyingContext.fetch(FetchDescriptor<HistoricalDataPoint>())
        let firstMiner = points.filter { $0.deviceId == "192.168.1.11" }
        let secondMiner = points.filter { $0.deviceId == "192.168.1.10" }
        XCTAssertEqual(firstMiner.count, 1_203)
        XCTAssertTrue(firstMiner.allSatisfy { $0.hashrate == 1 })
        XCTAssertEqual(secondMiner.count, 1_007)
        XCTAssertTrue(secondMiner.allSatisfy { $0.hashrate == 2 })
    }

    func testRelocateThreeAddressCyclePreservesEachMinersHistory() async throws {
        let schema = Schema([HistoricalDataPoint.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        let seedingContext = ModelContext(modelContainer)
        for (ipAddress, hashrate) in [
            ("192.168.1.10", 1.0),
            ("192.168.1.11", 2.0),
            ("192.168.1.12", 3.0),
        ] {
            seedingContext.insert(
                HistoricalDataPoint(
                    timestamp: Date(timeIntervalSince1970: 100),
                    hashrate: hashrate,
                    temperature: 50,
                    deviceId: ipAddress
                )
            )
        }
        try seedingContext.save()

        let relocator = HistoricalDataRelocator(modelContainer: modelContainer)
        try await relocator.relocate(
            [
                "192.168.1.10": "192.168.1.11",
                "192.168.1.11": "192.168.1.12",
                "192.168.1.12": "192.168.1.10",
            ],
            before: Date(timeIntervalSince1970: 200),
            operationID: UUID().uuidString
        )

        let verifyingContext = ModelContext(modelContainer)
        let points = try verifyingContext.fetch(FetchDescriptor<HistoricalDataPoint>())
        XCTAssertEqual(points.first { $0.deviceId == "192.168.1.11" }?.hashrate, 1)
        XCTAssertEqual(points.first { $0.deviceId == "192.168.1.12" }?.hashrate, 2)
        XCTAssertEqual(points.first { $0.deviceId == "192.168.1.10" }?.hashrate, 3)
    }

    func testRelocateLeavesSamplesWrittenAtReusedAddressAfterCutoff() async throws {
        let schema = Schema([HistoricalDataPoint.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        let seedingContext = ModelContext(modelContainer)
        seedingContext.insert(
            HistoricalDataPoint(
                timestamp: Date(timeIntervalSince1970: 100),
                hashrate: 1,
                temperature: 50,
                deviceId: "192.168.1.10"
            )
        )
        seedingContext.insert(
            HistoricalDataPoint(
                timestamp: Date(timeIntervalSince1970: 300),
                hashrate: 2,
                temperature: 51,
                deviceId: "192.168.1.10"
            )
        )
        try seedingContext.save()

        let relocator = HistoricalDataRelocator(modelContainer: modelContainer)
        try await relocator.relocate(
            ["192.168.1.10": "192.168.1.20"],
            before: Date(timeIntervalSince1970: 200),
            operationID: UUID().uuidString
        )

        let verifyingContext = ModelContext(modelContainer)
        let points = try verifyingContext.fetch(FetchDescriptor<HistoricalDataPoint>())
        XCTAssertEqual(points.first { $0.deviceId == "192.168.1.20" }?.hashrate, 1)
        XCTAssertEqual(points.first { $0.deviceId == "192.168.1.10" }?.hashrate, 2)
    }
}
