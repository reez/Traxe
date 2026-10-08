import Foundation
import XCTest

@testable import Traxe

@MainActor
final class DeviceListFleetMembershipTests: XCTestCase {
    func testPartialThenAllFailedRefreshPreservesTotalAcrossRelaunchAndMeasuredZero() async throws {
        actor Availability {
            var stage = 0
            func setStage(_ value: Int) { stage = value }
        }
        let availability = Availability()
        let suite = "DeviceListFleetMembershipTests.refresh.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let devices = [
            SavedDevice(name: "Miner A", ipAddress: "192.168.1.10"),
            SavedDevice(name: "Miner B", ipAddress: "192.168.1.11"),
        ]
        defaults.set(try JSONEncoder().encode(devices), forKey: "savedDevices")
        let dependencies = DeviceListViewModel.Dependencies(
            deviceManagement: .init(
                checkDevice: { ip in
                    let stage = await availability.stage
                    let first = ip == "192.168.1.10"
                    guard stage == 0 || (first && (stage == 1 || stage == 3)) else {
                        throw URLError(.cannotConnectToHost)
                    }
                    return DiscoveredDevice(
                        ip: ip, name: ip,
                        hashrate: stage == 3 ? 0 : (first ? 400 : 600),
                        temperature: 50, bestDiff: "1 M", power: first ? 12 : 18,
                        poolURL: nil, blockHeight: nil, networkDifficulty: nil
                    )
                },
                deleteDevice: { _ in },
                reorderDevices: { _ in }
            ),
            reloadWidget: {},
            autoRefreshOnLoad: false
        )
        let model = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        await model.updateAggregatedStats()
        XCTAssertEqual(model.totalHashRate, 1000)

        await availability.setStage(1)
        await model.updateAggregatedStats()
        XCTAssertEqual(model.totalHashRate, 400)
        XCTAssertEqual(model.fleetMetricSnapshot.includedDeviceIDs, ["192.168.1.10"])
        let measuredAt = model.fleetMetricSnapshot.measuredAt
        let cache = DeviceMetricsCache(defaults: defaults)
        XCTAssertEqual(cache.loadAll()["192.168.1.10"]?.isIncludedInLastKnownTotal, true)
        XCTAssertEqual(cache.loadAll()["192.168.1.11"]?.isIncludedInLastKnownTotal, false)

        await availability.setStage(2)
        await model.updateAggregatedStats()
        XCTAssertEqual(model.totalHashRate, 400)
        XCTAssertEqual(model.totalPower, 12)
        XCTAssertEqual(model.fleetMetricSnapshot.measuredAt, measuredAt)
        XCTAssertEqual(model.fleetMetricSnapshot.statusText, "Last known · 1 of 2 miners · stale")
        XCTAssertEqual(model.deviceMetrics["192.168.1.11"]?.hashrate, 600)
        let reloaded = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        await reloaded.updateAggregatedStats()
        XCTAssertEqual(reloaded.totalHashRate, 400)
        XCTAssertEqual(reloaded.fleetMetricSnapshot.includedDeviceIDs, ["192.168.1.10"])
        XCTAssertTrue(reloaded.fleetMetricSnapshot.isStale)

        await availability.setStage(3)
        await reloaded.updateAggregatedStats()
        XCTAssertEqual(reloaded.fleetMetricSnapshot.totalHashrate, 0)
        XCTAssertFalse(reloaded.fleetMetricSnapshot.isStale)
        await availability.setStage(4)
        await reloaded.updateAggregatedStats()
        XCTAssertEqual(reloaded.fleetMetricSnapshot.totalHashrate, 0)
        XCTAssertEqual(reloaded.fleetMetricSnapshot.includedDeviceIDs, ["192.168.1.10"])
        XCTAssertTrue(reloaded.fleetMetricSnapshot.isStale)
    }

    func testStaleMembershipFollowsAddressSwapAndPruningWithoutReaddingOtherMiner() throws {
        let suite = "DeviceListFleetMembershipTests.topology.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var first = SavedDevice(
            name: "Miner A", ipAddress: "192.168.1.10", macAddress: "AA:BB:CC:DD:EE:01"
        )
        var second = SavedDevice(
            name: "Miner B", ipAddress: "192.168.1.11", macAddress: "AA:BB:CC:DD:EE:02"
        )
        defaults.set(try JSONEncoder().encode([first, second]), forKey: "savedDevices")
        let measuredAt = Date(timeIntervalSince1970: 2_000_000_000)
        var firstReading = CachedDeviceMetrics(
            from: DeviceMetrics(hashrate: 400, timestamp: measuredAt, macAddress: first.macAddress),
            isReachable: false
        )
        firstReading.isIncludedInLastKnownTotal = true
        var secondReading = CachedDeviceMetrics(
            from: DeviceMetrics(hashrate: 600, timestamp: measuredAt, macAddress: second.macAddress),
            isReachable: false
        )
        secondReading.isIncludedInLastKnownTotal = false
        let cache = DeviceMetricsCache(defaults: defaults)
        cache.saveAll([first.ipAddress: firstReading, second.ipAddress: secondReading])
        let dependencies = DeviceListViewModel.Dependencies(
            deviceManagement: .init(
                checkDevice: { _ in throw URLError(.cannotConnectToHost) },
                deleteDevice: { _ in },
                reorderDevices: { _ in }
            ),
            reloadWidget: {},
            autoRefreshOnLoad: false
        )
        let model = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        XCTAssertEqual(model.totalHashRate, 400)

        first.ipAddress = "192.168.1.11"
        second.ipAddress = "192.168.1.10"
        defaults.set(try JSONEncoder().encode([first, second]), forKey: "savedDevices")
        model.synchronizeSavedDevices()
        XCTAssertEqual(model.totalHashRate, 400)
        XCTAssertEqual(model.fleetMetricSnapshot.includedDeviceIDs, [first.ipAddress])
        XCTAssertEqual(cache.loadAll()[first.ipAddress]?.isIncludedInLastKnownTotal, true)
        XCTAssertEqual(cache.loadAll()[second.ipAddress]?.isIncludedInLastKnownTotal, false)

        let added = SavedDevice(name: "New miner", ipAddress: "192.168.1.12")
        defaults.set(try JSONEncoder().encode([second, added]), forKey: "savedDevices")
        model.synchronizeSavedDevices()
        XCTAssertNil(model.fleetMetricSnapshot.totalHashrate)
        XCTAssertTrue(model.fleetMetricSnapshot.includedDeviceIDs.isEmpty)
        XCTAssertEqual(model.fleetMetricSnapshot.totalDevices, 2)
        XCTAssertNil(cache.loadAll()[first.ipAddress])
        let reloaded = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        XCTAssertNil(reloaded.fleetMetricSnapshot.totalHashrate)
        XCTAssertTrue(reloaded.fleetMetricSnapshot.includedDeviceIDs.isEmpty)
    }

    func testFailedRefreshUsesPartialTotalSavedByAnotherModel() async throws {
        actor Availability {
            var reachable: Set<String> = ["192.168.1.10", "192.168.1.11"]
            func setReachable(_ addresses: Set<String>) { reachable = addresses }
        }
        let availability = Availability()
        let suite = "DeviceListFleetMembershipTests.twoModels.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let devices = [
            SavedDevice(name: "Miner A", ipAddress: "192.168.1.10"),
            SavedDevice(name: "Miner B", ipAddress: "192.168.1.11"),
        ]
        defaults.set(try JSONEncoder().encode(devices), forKey: "savedDevices")
        let dependencies = DeviceListViewModel.Dependencies(
            deviceManagement: .init(
                checkDevice: { ip in
                    let reachable = await availability.reachable
                    guard reachable.contains(ip) else {
                        throw URLError(.cannotConnectToHost)
                    }
                    return DiscoveredDevice(
                        ip: ip, name: ip,
                        hashrate: ip == "192.168.1.10" ? (reachable.count == 1 ? 450 : 400) : 600,
                        temperature: 50, bestDiff: "1 M", power: 12,
                        poolURL: nil, blockHeight: nil, networkDifficulty: nil
                    )
                },
                deleteDevice: { _ in },
                reorderDevices: { _ in }
            ),
            reloadWidget: {},
            autoRefreshOnLoad: false
        )
        let first = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        await first.updateAggregatedStats()
        XCTAssertEqual(first.totalHashRate, 1000)
        let second = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        await availability.setReachable(["192.168.1.10"])
        await second.updateAggregatedStats()
        XCTAssertEqual(second.totalHashRate, 450)

        await availability.setReachable([])
        await first.updateAggregatedStats()
        XCTAssertEqual(first.totalHashRate, 450)
        XCTAssertEqual(first.fleetMetricSnapshot.includedDeviceIDs, ["192.168.1.10"])
        XCTAssertTrue(first.fleetMetricSnapshot.isStale)
        let reloaded = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        XCTAssertEqual(reloaded.totalHashRate, 450)
        XCTAssertEqual(reloaded.fleetMetricSnapshot.includedDeviceIDs, ["192.168.1.10"])
    }

    func testCacheKeepsNewerSameSecondMeasurementAndReadsLegacyDates() throws {
        let suite = "DeviceListFleetMembershipTests.precision.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let miner = SavedDevice(name: "Miner", ipAddress: "192.168.1.10")
        defaults.set(try JSONEncoder().encode([miner]), forKey: "savedDevices")
        let earlier = Date(timeIntervalSince1970: 100.1)
        let later = Date(timeIntervalSince1970: 100.8)
        let cache = DeviceMetricsCache(defaults: defaults)
        var initial = CachedDeviceMetrics(
            from: DeviceMetrics(hashrate: 400, timestamp: earlier), isReachable: false
        )
        initial.isIncludedInLastKnownTotal = true
        cache.saveAll([miner.ipAddress: initial])
        let model = DeviceListViewModel(
            defaults: defaults,
            dependencies: .init(
                deviceManagement: .init(
                    checkDevice: { _ in throw URLError(.cannotConnectToHost) },
                    deleteDevice: { _ in },
                    reorderDevices: { _ in }
                ),
                reloadWidget: {},
                autoRefreshOnLoad: false
            )
        )
        XCTAssertEqual(model.deviceMetrics[miner.ipAddress]?.timestamp, earlier)
        var newer = CachedDeviceMetrics(
            from: DeviceMetrics(hashrate: 450, timestamp: later), isReachable: false
        )
        newer.isIncludedInLastKnownTotal = true
        cache.saveAll([miner.ipAddress: newer])
        model.loadCacheAndComputeTotals()
        XCTAssertEqual(model.totalHashRate, 450)
        XCTAssertEqual(model.deviceMetrics[miner.ipAddress]?.timestamp, later)
        XCTAssertEqual(cache.loadAll()[miner.ipAddress]?.measurementDate, later)

        // Older app/watch readers still decode the ISO8601 field. New readers
        // also accept their caches when the optional precision field is absent.
        let data = try XCTUnwrap(defaults.data(forKey: "cachedDeviceMetricsV2"))
        struct LegacyReading: Decodable {
            let hashrate: Double
            let lastUpdated: Date
        }
        let legacyDecoder = JSONDecoder()
        legacyDecoder.dateDecodingStrategy = .iso8601
        let oldReader = try legacyDecoder.decode([String: LegacyReading].self, from: data)
        XCTAssertEqual(oldReader[miner.ipAddress]?.hashrate, 450)
        XCTAssertEqual(oldReader[miner.ipAddress]?.lastUpdated, Date(timeIntervalSince1970: 100))
        var legacy = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
        )
        legacy[miner.ipAddress]?.removeValue(forKey: "lastUpdatedReferenceTime")
        defaults.set(
            try JSONSerialization.data(withJSONObject: legacy), forKey: "cachedDeviceMetricsV2"
        )
        XCTAssertEqual(
            cache.loadAll()[miner.ipAddress]?.measurementDate, Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(cache.loadAll()[miner.ipAddress]?.hashrate, 450)
    }

}
