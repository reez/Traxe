import Foundation
import XCTest

@testable import Traxe

final class FleetMetricSnapshotTests: XCTestCase {
    func testNoResponsesPreserveKnownTotalAndOldestMeasurement() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshot = FleetMetricSnapshot.make(
            readings: [
                .init(
                    id: "a",
                    hashrate: 400,
                    power: 12,
                    measuredAt: now.addingTimeInterval(-600),
                    isReachable: false
                ),
                .init(
                    id: "b",
                    hashrate: 600,
                    power: 18,
                    measuredAt: now.addingTimeInterval(-300),
                    isReachable: false
                ),
            ],
            totalDevices: 2,
            referenceDate: now
        )
        XCTAssertEqual(snapshot.totalHashrate, 1000)
        XCTAssertEqual(snapshot.totalPower, 30)
        XCTAssertEqual(snapshot.measuredAt, now.addingTimeInterval(-600))
        XCTAssertTrue(snapshot.isStale)
        XCTAssertEqual(snapshot.statusText, "Last known · stale")
    }

    func testPartialResponseExcludesOldReadingAndReportsCoverage() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshot = FleetMetricSnapshot.make(
            readings: [
                .init(id: "a", hashrate: 400, measuredAt: now, isReachable: true),
                .init(
                    id: "b",
                    hashrate: 600,
                    measuredAt: now.addingTimeInterval(-300),
                    isReachable: false
                ),
            ],
            totalDevices: 3,
            referenceDate: now
        )
        XCTAssertEqual(snapshot.totalHashrate, 400)
        XCTAssertEqual(snapshot.includedDeviceIDs, ["a"])
        XCTAssertEqual(snapshot.measuredAt, now)
        XCTAssertFalse(snapshot.isStale)
        XCTAssertTrue(snapshot.isPartial)
        XCTAssertEqual(snapshot.statusText, "1 of 3 miners reporting")
    }

    func testReportedZeroRemainsMeasuredZero() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshot = FleetMetricSnapshot.make(
            readings: [.init(id: "paused", hashrate: 0, measuredAt: now, isReachable: true)],
            totalDevices: 1,
            referenceDate: now
        )
        XCTAssertEqual(snapshot.totalHashrate, 0)
        XCTAssertFalse(snapshot.isStale)
        XCTAssertFalse(snapshot.isPartial)
        XCTAssertEqual(snapshot.statusText, "1 of 1 miners reporting")
    }

    func testNoCacheIsUnavailableRatherThanZero() {
        let snapshot = FleetMetricSnapshot.make(readings: [], totalDevices: 2)
        XCTAssertNil(snapshot.totalHashrate)
        XCTAssertNil(snapshot.measuredAt)
        XCTAssertEqual(snapshot.statusText, "No readings yet")
    }

    func testLegacyAndExpiredReachabilityAreExplicitlyStale() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        for reachability in [nil, true] as [Bool?] {
            let snapshot = FleetMetricSnapshot.make(
                readings: [
                    .init(
                        id: "a",
                        hashrate: 600,
                        measuredAt: now.addingTimeInterval(-3600),
                        isReachable: reachability
                    )
                ],
                totalDevices: 1,
                referenceDate: now
            )
            XCTAssertEqual(snapshot.totalHashrate, 600)
            XCTAssertTrue(snapshot.isStale)
            XCTAssertTrue(snapshot.reportingDeviceIDs.isEmpty)
        }
    }

    func testResponseWithoutHashrateDoesNotTurnCachedValueIntoFreshReading() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshot = FleetMetricSnapshot.make(
            readings: [
                .init(
                    id: "a",
                    hashrate: 600,
                    measuredAt: now.addingTimeInterval(-3600),
                    isReachable: true,
                    isHashrateReporting: false,
                    observedAt: now
                )
            ],
            totalDevices: 1,
            referenceDate: now
        )
        XCTAssertNil(snapshot.totalHashrate)
        XCTAssertNil(snapshot.measuredAt)
        XCTAssertEqual(snapshot.reportingDeviceIDs, ["a"])
        XCTAssertEqual(snapshot.statusText, "Hash rate unavailable")
    }

    func testAllResponsesCombineKnownMeasurementsWithoutUnknownZero() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshot = FleetMetricSnapshot.make(
            readings: [
                .init(id: "a", hashrate: 400, measuredAt: now, isReachable: true),
                .init(id: "b", hashrate: 600, measuredAt: now, isReachable: true),
                .init(id: "unknown", hashrate: nil, measuredAt: now, isReachable: true),
            ],
            totalDevices: 3,
            referenceDate: now
        )
        XCTAssertEqual(snapshot.totalHashrate, 1000)
        XCTAssertEqual(snapshot.reportingDeviceIDs.count, 3)
        XCTAssertEqual(snapshot.includedDeviceIDs.count, 2)
        XCTAssertEqual(snapshot.statusText, "2 of 3 miners with hash rate")
    }
    func testStaleTotalExcludesOldMeasurementsAndExplainsExcludedWatchRows() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let recent = FleetMetricSnapshot.Reading(
            id: "recent",
            hashrate: 600,
            power: 12,
            measuredAt: now,
            isReachable: false
        )
        let old = FleetMetricSnapshot.Reading(
            id: "old",
            hashrate: 800,
            power: 18,
            measuredAt: now.addingTimeInterval(-3 * 24 * 60 * 60),
            isReachable: false
        )
        let snapshot = FleetMetricSnapshot.make(
            readings: [recent, old],
            totalDevices: 2,
            referenceDate: now
        )
        XCTAssertEqual(snapshot.totalHashrate, 600)
        XCTAssertEqual(snapshot.totalPower, 12)
        XCTAssertEqual(snapshot.measuredAt, now)
        XCTAssertEqual(snapshot.includedDeviceIDs, ["recent"])
        XCTAssertEqual(snapshot.statusText, "Last known · 1 of 2 miners · stale")
        XCTAssertEqual(snapshot.compactStatusText, "1/2 stale")
        XCTAssertEqual(snapshot.rowStatusText(for: recent), "Last known · stale")
        XCTAssertEqual(snapshot.rowStatusText(for: old), "Last known · excluded from total")
    }

    func testUnknownOrInvalidNewReadingsDoNotAnchorStaleCohort() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let measuredAt = now.addingTimeInterval(-3 * 24 * 60 * 60)
        let snapshot = FleetMetricSnapshot.make(
            readings: [
                .init(id: "known", hashrate: 600, measuredAt: measuredAt, isReachable: false),
                .init(id: "unknown", hashrate: nil, measuredAt: now, isReachable: false),
                .init(id: "nonfinite", hashrate: .infinity, measuredAt: now, isReachable: false),
                .init(id: "negative", hashrate: -1, measuredAt: now, isReachable: false),
            ],
            totalDevices: 4,
            referenceDate: now
        )
        XCTAssertEqual(snapshot.totalHashrate, 600)
        XCTAssertEqual(snapshot.includedDeviceIDs, ["known"])
        XCTAssertEqual(snapshot.measuredAt, measuredAt)
        XCTAssertTrue(snapshot.isStale)
    }

    func testStaleCohortIsRelativeToNewestValidMeasurementIncludingZeroAndBoundary() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let newest = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let snapshot = FleetMetricSnapshot.make(
            readings: [
                .init(id: "paused", hashrate: 0, measuredAt: newest, isReachable: false),
                .init(
                    id: "boundary",
                    hashrate: 600,
                    measuredAt: newest.addingTimeInterval(-1800),
                    isReachable: false
                ),
                .init(
                    id: "older",
                    hashrate: 800,
                    measuredAt: newest.addingTimeInterval(-1801),
                    isReachable: false
                ),
            ],
            totalDevices: 3,
            referenceDate: now
        )
        XCTAssertEqual(snapshot.totalHashrate, 600)
        XCTAssertEqual(snapshot.includedDeviceIDs, ["paused", "boundary"])
        XCTAssertEqual(snapshot.measuredAt, newest.addingTimeInterval(-1800))
        XCTAssertTrue(snapshot.isStale)
    }

    func testRecordedMembershipPreservesPartialTotalAfterAllReachabilityExpires() {
        let measuredAt = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshot = FleetMetricSnapshot.make(
            readings: [
                .init(
                    id: "included", hashrate: 0, power: 12, measuredAt: measuredAt,
                    isReachable: true, isIncludedInLastKnownTotal: true
                ),
                .init(
                    id: "excluded", hashrate: 600, power: 18, measuredAt: measuredAt,
                    isReachable: false, isIncludedInLastKnownTotal: false
                ),
                .init(
                    id: "added", hashrate: 800, power: 20, measuredAt: measuredAt,
                    isReachable: false
                ),
            ],
            totalDevices: 3,
            referenceDate: measuredAt.addingTimeInterval(3600)
        )
        XCTAssertEqual(snapshot.totalHashrate, 0)
        XCTAssertEqual(snapshot.totalPower, 12)
        XCTAssertEqual(snapshot.includedDeviceIDs, ["included"])
        XCTAssertEqual(snapshot.measuredAt, measuredAt)
        XCTAssertEqual(snapshot.statusText, "Last known · 1 of 3 miners · stale")
    }

    func testRemovingLastIncludedMinerDoesNotReviveAnExcludedReading() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshot = FleetMetricSnapshot.make(
            readings: [
                .init(
                    id: "excluded", hashrate: 600, measuredAt: now,
                    isReachable: false, isIncludedInLastKnownTotal: false
                )
            ],
            totalDevices: 1,
            referenceDate: now
        )
        XCTAssertNil(snapshot.totalHashrate)
        XCTAssertNil(snapshot.measuredAt)
        XCTAssertTrue(snapshot.includedDeviceIDs.isEmpty)
        XCTAssertTrue(snapshot.isStale)
    }

}
