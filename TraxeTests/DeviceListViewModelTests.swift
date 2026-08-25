import Foundation
import SwiftData
import XCTest

@testable import Traxe

@MainActor
final class DeviceListViewModelTests: XCTestCase {
    func testLoadDevicesPersistsIdentifiersForLegacyMiners() throws {
        let defaults = makeIsolatedDefaults(suiteName: "DeviceListViewModelTests.legacyIDs")
        defaults.set(
            Data(#"[{"name":"Miner A","ipAddress":"192.168.1.10"}]"#.utf8),
            forKey: "savedDevices"
        )
        var dependencies = makeDependencies(responses: [:])
        dependencies.autoRefreshOnLoad = false

        let firstViewModel = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        let firstID = try XCTUnwrap(firstViewModel.savedDevices.first?.id)
        let persisted = try JSONDecoder().decode(
            [SavedDevice].self,
            from: XCTUnwrap(defaults.data(forKey: "savedDevices"))
        )
        XCTAssertEqual(persisted.first?.id, firstID)
        XCTAssertFalse(try XCTUnwrap(persisted.first).needsIdentifierMigration)

        let reloadedViewModel = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        XCTAssertEqual(reloadedViewModel.savedDevices.first?.id, firstID)
    }

    func testUpdateAggregatedStatsPopulatesMetricsTotalsAndReachability() async {
        let responses: [String: DiscoveredDevice] = [
            "192.168.1.10": makeDiscoveredDevice(
                ip: "192.168.1.10",
                name: "Miner A",
                hashrate: 1000,
                power: 20,
                bestDiff: "5 M"
            ),
            "192.168.1.11": makeDiscoveredDevice(
                ip: "192.168.1.11",
                name: "Miner B",
                hashrate: 800,
                power: 16,
                bestDiff: "7 M"
            ),
        ]

        var dependencies = makeDependencies(responses: responses)
        dependencies.autoRefreshOnLoad = false

        let defaults = makeIsolatedDefaults(suiteName: "DeviceListViewModelTests.stats")
        let viewModel = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        viewModel.savedDevices = [
            SavedDevice(name: "Miner A", ipAddress: "192.168.1.10"),
            SavedDevice(name: "Miner B", ipAddress: "192.168.1.11"),
        ]
        viewModel.deviceMetrics = [:]

        await viewModel.updateAggregatedStats()

        XCTAssertEqual(viewModel.reachableIPs, Set(["192.168.1.10", "192.168.1.11"]))
        XCTAssertEqual(viewModel.deviceMetrics.count, 2)
        XCTAssertEqual(viewModel.totalHashRate, 1800, accuracy: 0.001)
        XCTAssertEqual(viewModel.totalPower, 36, accuracy: 0.001)
        XCTAssertEqual(viewModel.bestOverallDiff, 7.0, accuracy: 0.001)
        XCTAssertFalse(viewModel.isLoadingAggregatedStats)
    }

    func testUpdateAggregatedStatsExcludesUnreachableDevicesFromReachability() async {
        let responses: [String: DiscoveredDevice] = [
            "192.168.1.20": makeDiscoveredDevice(
                ip: "192.168.1.20",
                name: "Miner Reachable",
                hashrate: 500,
                power: 12,
                bestDiff: "3 M"
            )
        ]

        var dependencies = makeDependencies(responses: responses)
        dependencies.autoRefreshOnLoad = false

        let defaults = makeIsolatedDefaults(suiteName: "DeviceListViewModelTests.reachability")
        let viewModel = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        viewModel.savedDevices = [
            SavedDevice(name: "Miner Reachable", ipAddress: "192.168.1.20"),
            SavedDevice(name: "Miner Offline", ipAddress: "192.168.1.21"),
        ]
        viewModel.deviceMetrics = [:]

        await viewModel.updateAggregatedStats()

        XCTAssertEqual(viewModel.reachableIPs, Set(["192.168.1.20"]))
        XCTAssertNotNil(viewModel.deviceMetrics["192.168.1.20"])
        XCTAssertNil(viewModel.deviceMetrics["192.168.1.21"])
    }

    func testRefreshLearnsMACAddressForMinerSavedWithoutOne() async throws {
        let defaults = makeIsolatedDefaults(suiteName: "DeviceListViewModelTests.learnMAC")
        DeviceManagementService.sharedDefaultsOverride = defaults
        DeviceManagementService.reloadWidgetTimelines = { _ in }
        defer { DeviceManagementService.sharedDefaultsOverride = nil }
        try saveSavedDevices(
            [SavedDevice(name: "Miner A", ipAddress: "192.168.1.10")],
            in: defaults
        )

        var dependencies = makeDependencies(responses: [
            "192.168.1.10": DiscoveredDevice(
                ip: "192.168.1.10",
                name: "Miner A",
                hashrate: 500,
                temperature: 50,
                bestDiff: "1 M",
                power: 10,
                poolURL: nil,
                blockHeight: nil,
                networkDifficulty: nil,
                macAddress: "aa:bb:cc:dd:ee:01"
            )
        ])
        dependencies.autoRefreshOnLoad = false
        dependencies.deviceManagement.recordMACAddress = { macAddress, ipAddress in
            try DeviceManagementService.recordMACAddress(macAddress, forDeviceAt: ipAddress)
        }
        let viewModel = DeviceListViewModel(defaults: defaults, dependencies: dependencies)

        await viewModel.updateAggregatedStats()

        XCTAssertEqual(viewModel.savedDevices.first?.macAddress, "AA:BB:CC:DD:EE:01")
        XCTAssertEqual(viewModel.reachableIPs, ["192.168.1.10"])
        let stored = try JSONDecoder().decode(
            [SavedDevice].self,
            from: XCTUnwrap(defaults.data(forKey: "savedDevices"))
        )
        XCTAssertEqual(stored.first?.macAddress, "AA:BB:CC:DD:EE:01")
        XCTAssertEqual(
            defaults.dictionary(forKey: "savedDeviceMACAddresses") as? [String: String],
            ["192.168.1.10": "AA:BB:CC:DD:EE:01"]
        )
    }

    func testRefreshTreatsDifferentMACAtSavedAddressAsUnreachable() async {
        var dependencies = makeDependencies(responses: [
            "192.168.1.10": DiscoveredDevice(
                ip: "192.168.1.10",
                name: "Some other miner",
                hashrate: 500,
                temperature: 50,
                bestDiff: "1 M",
                power: 10,
                poolURL: nil,
                blockHeight: nil,
                networkDifficulty: nil,
                macAddress: "AA:BB:CC:DD:EE:99"
            )
        ])
        dependencies.autoRefreshOnLoad = false
        let defaults = makeIsolatedDefaults(suiteName: "DeviceListViewModelTests.macMismatch")
        let viewModel = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        viewModel.savedDevices = [
            SavedDevice(name: "Miner A", ipAddress: "192.168.1.10", macAddress: "AA:BB:CC:DD:EE:01")
        ]
        viewModel.deviceMetrics = [:]

        await viewModel.updateAggregatedStats()

        XCTAssertEqual(viewModel.reachableIPs, [])
        XCTAssertNil(viewModel.deviceMetrics["192.168.1.10"])
        XCTAssertEqual(viewModel.savedDevices.first?.macAddress, "AA:BB:CC:DD:EE:01")
    }

    func testRefreshFindsMovedMinerByMACAndFollowsItToNewAddress() async throws {
        let defaults = makeIsolatedDefaults(suiteName: "DeviceListViewModelTests.relocate")
        DeviceManagementService.sharedDefaultsOverride = defaults
        DeviceManagementService.reloadWidgetTimelines = { _ in }
        defer { DeviceManagementService.sharedDefaultsOverride = nil }
        try saveSavedDevices(
            [
                SavedDevice(
                    name: "Miner A",
                    ipAddress: "192.168.1.10",
                    macAddress: "AA:BB:CC:DD:EE:01"
                )
            ],
            in: defaults
        )
        defaults.set("192.168.1.10", forKey: "bitaxeIPAddress")

        let movedMiner = DiscoveredDevice(
            ip: "192.168.1.42",
            name: "Miner A",
            hashrate: 700,
            temperature: 55,
            bestDiff: "2 M",
            power: 14,
            poolURL: nil,
            blockHeight: nil,
            networkDifficulty: nil,
            macAddress: "AA:BB:CC:DD:EE:01"
        )
        var dependencies = makeDependencies(responses: ["192.168.1.42": movedMiner])
        dependencies.autoRefreshOnLoad = false
        dependencies.deviceManagement.scanLocalNetwork = { _ in [movedMiner] }
        dependencies.deviceManagement.relocateDevices = { discoveredDevices in
            try DeviceManagementService.relocateDevices(matching: discoveredDevices)
        }
        let viewModel = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        viewModel.deviceMetrics = ["192.168.1.10": DeviceMetrics(hashrate: 650, temperature: 52)]

        await viewModel.updateAggregatedStats()

        XCTAssertEqual(viewModel.savedDevices.map(\.ipAddress), ["192.168.1.42"])
        XCTAssertEqual(viewModel.savedDevices.first?.macAddress, "AA:BB:CC:DD:EE:01")
        XCTAssertEqual(viewModel.recentRelocations, ["192.168.1.10": "192.168.1.42"])
        XCTAssertNil(viewModel.deviceMetrics["192.168.1.10"])
        XCTAssertEqual(viewModel.deviceMetrics["192.168.1.42"]?.hashrate ?? 0, 650, accuracy: 0.001)
        XCTAssertEqual(defaults.array(forKey: "savedDeviceIPs") as? [String], ["192.168.1.42"])
        XCTAssertEqual(defaults.string(forKey: "bitaxeIPAddress"), "192.168.1.42")

        // The next refresh fetches from the new address like any other saved miner.
        await viewModel.updateAggregatedStats()

        XCTAssertEqual(viewModel.reachableIPs, ["192.168.1.42"])
        XCTAssertEqual(viewModel.deviceMetrics["192.168.1.42"]?.hashrate ?? 0, 700, accuracy: 0.001)
    }

    func testLoadDevicesPreservesBothMinersMetricsThroughAddressSwap() throws {
        let defaults = makeIsolatedDefaults(suiteName: "DeviceListViewModelTests.addressSwap")
        let first = SavedDevice(
            name: "Miner A",
            ipAddress: "192.168.1.10",
            macAddress: "AA:BB:CC:DD:EE:01"
        )
        let second = SavedDevice(
            name: "Miner B",
            ipAddress: "192.168.1.11",
            macAddress: "AA:BB:CC:DD:EE:02"
        )
        try saveSavedDevices([first, second], in: defaults)
        let cachedAt = Date(timeIntervalSince1970: 100)
        var firstCachedMetrics = CachedDeviceMetrics(from: DeviceMetrics(hashrate: 100))
        firstCachedMetrics.lastUpdated = cachedAt
        var secondCachedMetrics = CachedDeviceMetrics(from: DeviceMetrics(hashrate: 200))
        secondCachedMetrics.lastUpdated = cachedAt
        let cacheEncoder = JSONEncoder()
        cacheEncoder.dateEncodingStrategy = .iso8601
        defaults.set(
            try cacheEncoder.encode([
                "192.168.1.10": firstCachedMetrics,
                "192.168.1.11": secondCachedMetrics,
            ]),
            forKey: "cachedDeviceMetricsV2"
        )
        var dependencies = makeDependencies(responses: [:])
        dependencies.autoRefreshOnLoad = false
        let viewModel = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        viewModel.deviceMetrics = [
            "192.168.1.10": DeviceMetrics(hashrate: 100),
            "192.168.1.11": DeviceMetrics(hashrate: 200),
        ]
        viewModel.reachableIPs = ["192.168.1.10", "192.168.1.11"]

        var movedFirst = first
        movedFirst.ipAddress = "192.168.1.11"
        var movedSecond = second
        movedSecond.ipAddress = "192.168.1.10"
        try saveSavedDevices([movedFirst, movedSecond], in: defaults)
        viewModel.loadDevices()

        XCTAssertEqual(viewModel.savedDevices.map(\.ipAddress), ["192.168.1.11", "192.168.1.10"])
        XCTAssertEqual(
            viewModel.recentRelocations,
            ["192.168.1.10": "192.168.1.11", "192.168.1.11": "192.168.1.10"]
        )
        XCTAssertEqual(viewModel.deviceMetrics["192.168.1.11"]?.hashrate ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(viewModel.deviceMetrics["192.168.1.10"]?.hashrate ?? 0, 200, accuracy: 0.001)
        XCTAssertTrue(viewModel.reachableIPs.isEmpty)
        XCTAssertEqual(viewModel.totalHashRate, 300)
        let cacheDecoder = JSONDecoder()
        cacheDecoder.dateDecodingStrategy = .iso8601
        let remappedCache = try cacheDecoder.decode(
            [String: CachedDeviceMetrics].self,
            from: XCTUnwrap(defaults.data(forKey: "cachedDeviceMetricsV2"))
        )
        XCTAssertEqual(remappedCache["192.168.1.11"]?.hashrate, 100)
        XCTAssertEqual(remappedCache["192.168.1.10"]?.hashrate, 200)
        XCTAssertEqual(remappedCache["192.168.1.11"]?.lastUpdated, cachedAt)
        XCTAssertEqual(remappedCache["192.168.1.10"]?.lastUpdated, cachedAt)

        let relaunchedViewModel = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        XCTAssertEqual(
            relaunchedViewModel.deviceMetrics["192.168.1.11"]?.hashrate ?? 0,
            100,
            accuracy: 0.001
        )
        XCTAssertEqual(
            relaunchedViewModel.deviceMetrics["192.168.1.10"]?.hashrate ?? 0,
            200,
            accuracy: 0.001
        )
    }

    func testRelaunchRecoversSwappedMetricsAndHistoryFromPersistedMove() async throws {
        let defaults = makeIsolatedDefaults(suiteName: "DeviceListViewModelTests.crashRecovery")
        let operationID = UUID().uuidString
        let cutoff = Date().addingTimeInterval(60)
        var first = SavedDevice(
            name: "Miner A", ipAddress: "192.168.1.11",
            macAddress: "AA:BB:CC:DD:EE:01"
        )
        first.relocationRecords = [
            .init(
                operationID: operationID, sequence: 1,
                previousIPAddress: "192.168.1.10",
                currentIPAddress: "192.168.1.11", cutoff: cutoff
            )
        ]
        var second = SavedDevice(
            name: "Miner B", ipAddress: "192.168.1.10",
            macAddress: "AA:BB:CC:DD:EE:02"
        )
        second.relocationRecords = [
            .init(
                operationID: operationID, sequence: 1,
                previousIPAddress: "192.168.1.11",
                currentIPAddress: "192.168.1.10", cutoff: cutoff
            )
        ]
        try saveSavedDevices([first, second], in: defaults)
        let cacheEncoder = JSONEncoder()
        cacheEncoder.dateEncodingStrategy = .iso8601
        defaults.set(
            try cacheEncoder.encode([
                "192.168.1.10": CachedDeviceMetrics(from: DeviceMetrics(hashrate: 100)),
                "192.168.1.11": CachedDeviceMetrics(from: DeviceMetrics(hashrate: 200)),
            ]),
            forKey: "cachedDeviceMetricsV2"
        )
        var dependencies = makeDependencies(responses: [:])
        dependencies.autoRefreshOnLoad = false

        let modelContainer = try makeInMemoryModelContainer()
        let seedingContext = ModelContext(modelContainer)
        seedingContext.insert(
            HistoricalDataPoint(
                timestamp: Date(timeIntervalSince1970: 100),
                hashrate: 100, temperature: 50, deviceId: "192.168.1.10"
            )
        )
        seedingContext.insert(
            HistoricalDataPoint(
                timestamp: Date(timeIntervalSince1970: 100),
                hashrate: 200, temperature: 50, deviceId: "192.168.1.11"
            )
        )
        try seedingContext.save()

        let relaunched = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        XCTAssertEqual(relaunched.deviceMetrics["192.168.1.11"]?.hashrate, 100)
        XCTAssertEqual(relaunched.deviceMetrics["192.168.1.10"]?.hashrate, 200)
        XCTAssertEqual(relaunched.savedDevices.flatMap(\.relocationRecords).count, 0)
        XCTAssertNotNil(defaults.data(forKey: "pendingHistoryRelocationsV1"))
        XCTAssertTrue(relaunched.configureModelContextIfNeeded(modelContainer.mainContext))
        for _ in 0..<500 {
            if defaults.data(forKey: "pendingHistoryRelocationsV1") == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNil(defaults.data(forKey: "pendingHistoryRelocationsV1"))
        let points = try ModelContext(modelContainer).fetch(FetchDescriptor<HistoricalDataPoint>())
        XCTAssertEqual(points.first { $0.deviceId == "192.168.1.11" }?.hashrate, 100)
        XCTAssertEqual(points.first { $0.deviceId == "192.168.1.10" }?.hashrate, 200)

        let secondWindow = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        XCTAssertEqual(secondWindow.deviceMetrics["192.168.1.11"]?.hashrate, 100)
        XCTAssertEqual(secondWindow.deviceMetrics["192.168.1.10"]?.hashrate, 200)
        XCTAssertNil(defaults.data(forKey: "pendingHistoryRelocationsV1"))
    }

    func testRecoveryDoesNotGiveVacatedAddressCacheToNewMiner() throws {
        let defaults = makeIsolatedDefaults(suiteName: "DeviceListViewModelTests.reusedIP")
        var moved = SavedDevice(
            name: "Miner A", ipAddress: "192.168.1.11",
            macAddress: "AA:BB:CC:DD:EE:01"
        )
        moved.relocationRecords = [
            .init(
                operationID: UUID().uuidString, sequence: 1,
                previousIPAddress: "192.168.1.10",
                currentIPAddress: "192.168.1.11",
                cutoff: Date().addingTimeInterval(60)
            )
        ]
        let newMiner = SavedDevice(name: "Miner B", ipAddress: "192.168.1.10")
        try saveSavedDevices([moved, newMiner], in: defaults)
        let cacheEncoder = JSONEncoder()
        cacheEncoder.dateEncodingStrategy = .iso8601
        defaults.set(
            try cacheEncoder.encode([
                "192.168.1.10": CachedDeviceMetrics(from: DeviceMetrics(hashrate: 100))
            ]),
            forKey: "cachedDeviceMetricsV2"
        )
        var dependencies = makeDependencies(responses: [:])
        dependencies.autoRefreshOnLoad = false

        let relaunched = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        XCTAssertEqual(relaunched.deviceMetrics["192.168.1.11"]?.hashrate, 100)
        XCTAssertNil(relaunched.deviceMetrics["192.168.1.10"])
        let cacheDecoder = JSONDecoder()
        cacheDecoder.dateDecodingStrategy = .iso8601
        let recoveredCache = try cacheDecoder.decode(
            [String: CachedDeviceMetrics].self,
            from: XCTUnwrap(defaults.data(forKey: "cachedDeviceMetricsV2"))
        )
        XCTAssertEqual(recoveredCache["192.168.1.11"]?.hashrate, 100)
        XCTAssertNil(recoveredCache["192.168.1.10"])
    }

    func testLiveSwapRecoveryUsesPreviousMemoryMetricsWhenCacheIsEmpty() throws {
        let defaults = makeIsolatedDefaults(suiteName: "DeviceListViewModelTests.emptySwapCache")
        let first = SavedDevice(
            name: "Miner A", ipAddress: "192.168.1.10",
            macAddress: "AA:BB:CC:DD:EE:01"
        )
        let second = SavedDevice(
            name: "Miner B", ipAddress: "192.168.1.11",
            macAddress: "AA:BB:CC:DD:EE:02"
        )
        try saveSavedDevices([first, second], in: defaults)
        var dependencies = makeDependencies(responses: [:])
        dependencies.autoRefreshOnLoad = false
        let viewModel = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        viewModel.deviceMetrics = [
            "192.168.1.10": DeviceMetrics(hashrate: 100),
            "192.168.1.11": DeviceMetrics(hashrate: 200),
        ]

        let operationID = UUID().uuidString
        let cutoff = Date()
        var movedFirst = first
        movedFirst.ipAddress = "192.168.1.11"
        movedFirst.relocationRecords = [
            .init(
                operationID: operationID, sequence: 1,
                previousIPAddress: "192.168.1.10",
                currentIPAddress: "192.168.1.11", cutoff: cutoff
            )
        ]
        var movedSecond = second
        movedSecond.ipAddress = "192.168.1.10"
        movedSecond.relocationRecords = [
            .init(
                operationID: operationID, sequence: 1,
                previousIPAddress: "192.168.1.11",
                currentIPAddress: "192.168.1.10", cutoff: cutoff
            )
        ]
        try saveSavedDevices([movedFirst, movedSecond], in: defaults)
        viewModel.loadDevices()

        XCTAssertEqual(viewModel.deviceMetrics["192.168.1.11"]?.hashrate, 100)
        XCTAssertEqual(viewModel.deviceMetrics["192.168.1.10"]?.hashrate, 200)
        let cacheDecoder = JSONDecoder()
        cacheDecoder.dateDecodingStrategy = .iso8601
        let recoveredCache = try cacheDecoder.decode(
            [String: CachedDeviceMetrics].self,
            from: XCTUnwrap(defaults.data(forKey: "cachedDeviceMetricsV2"))
        )
        XCTAssertEqual(recoveredCache["192.168.1.11"]?.hashrate, 100)
        XCTAssertEqual(recoveredCache["192.168.1.10"]?.hashrate, 200)
    }

    func testRelaunchReplaysConsecutiveRecordedMovesInOrder() async throws {
        let defaults = makeIsolatedDefaults(suiteName: "DeviceListViewModelTests.moveTrail")
        var moved = SavedDevice(
            name: "Miner A", ipAddress: "192.168.1.12",
            macAddress: "AA:BB:CC:DD:EE:01"
        )
        let cutoff = Date().addingTimeInterval(60)
        moved.relocationRecords = [
            .init(
                operationID: UUID().uuidString, sequence: 1,
                previousIPAddress: "192.168.1.10",
                currentIPAddress: "192.168.1.11", cutoff: cutoff
            ),
            .init(
                operationID: UUID().uuidString, sequence: 2,
                previousIPAddress: "192.168.1.11",
                currentIPAddress: "192.168.1.12", cutoff: cutoff
            ),
        ]
        try saveSavedDevices([moved], in: defaults)
        let cacheEncoder = JSONEncoder()
        cacheEncoder.dateEncodingStrategy = .iso8601
        defaults.set(
            try cacheEncoder.encode([
                "192.168.1.10": CachedDeviceMetrics(from: DeviceMetrics(hashrate: 500))
            ]),
            forKey: "cachedDeviceMetricsV2"
        )
        var dependencies = makeDependencies(responses: [:])
        dependencies.autoRefreshOnLoad = false
        let modelContainer = try makeInMemoryModelContainer()
        let seedingContext = ModelContext(modelContainer)
        seedingContext.insert(
            HistoricalDataPoint(
                timestamp: Date(timeIntervalSince1970: 100),
                hashrate: 500, temperature: 50, deviceId: "192.168.1.10"
            )
        )
        try seedingContext.save()

        let relaunched = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        XCTAssertEqual(relaunched.deviceMetrics["192.168.1.12"]?.hashrate, 500)
        XCTAssertTrue(relaunched.configureModelContextIfNeeded(modelContainer.mainContext))
        for _ in 0..<500 {
            if defaults.data(forKey: "pendingHistoryRelocationsV1") == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNil(defaults.data(forKey: "pendingHistoryRelocationsV1"))
        let points = try ModelContext(modelContainer).fetch(FetchDescriptor<HistoricalDataPoint>())
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.deviceId, "192.168.1.12")
    }

    func testTwoWindowsQueueOneHistorySwap() async throws {
        let suiteName = "DeviceListViewModelTests.twoWindowSwap.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let secondWindowDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let first = SavedDevice(
            name: "Miner A",
            ipAddress: "192.168.1.10",
            macAddress: "AA:BB:CC:DD:EE:01"
        )
        let second = SavedDevice(
            name: "Miner B",
            ipAddress: "192.168.1.11",
            macAddress: "AA:BB:CC:DD:EE:02"
        )
        try saveSavedDevices([first, second], in: defaults)
        var dependencies = makeDependencies(responses: [:])
        dependencies.autoRefreshOnLoad = false
        let firstWindow = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        let secondWindow = DeviceListViewModel(
            defaults: secondWindowDefaults,
            dependencies: dependencies
        )

        let modelContainer = try makeInMemoryModelContainer()
        let seedingContext = ModelContext(modelContainer)
        seedingContext.insert(
            HistoricalDataPoint(
                timestamp: Date(timeIntervalSince1970: 100),
                hashrate: 100,
                temperature: 50,
                deviceId: "192.168.1.10"
            )
        )
        seedingContext.insert(
            HistoricalDataPoint(
                timestamp: Date(timeIntervalSince1970: 100),
                hashrate: 200,
                temperature: 51,
                deviceId: "192.168.1.11"
            )
        )
        try seedingContext.save()
        let firstContext = ModelContext(modelContainer)
        let secondContext = ModelContext(modelContainer)
        XCTAssertTrue(firstWindow.configureModelContextIfNeeded(firstContext))
        XCTAssertTrue(secondWindow.configureModelContextIfNeeded(secondContext))

        var movedFirst = first
        movedFirst.ipAddress = "192.168.1.11"
        var movedSecond = second
        movedSecond.ipAddress = "192.168.1.10"
        try saveSavedDevices([movedFirst, movedSecond], in: defaults)
        firstWindow.loadDevices()
        secondWindow.loadDevices()

        XCTAssertNotNil(defaults.data(forKey: "pendingHistoryRelocationsV1"))
        for _ in 0..<500 {
            if defaults.data(forKey: "pendingHistoryRelocationsV1") == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNil(defaults.data(forKey: "pendingHistoryRelocationsV1"))
        let verifyingContext = ModelContext(modelContainer)
        let points = try verifyingContext.fetch(FetchDescriptor<HistoricalDataPoint>())
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.first { $0.deviceId == "192.168.1.11" }?.hashrate, 100)
        XCTAssertEqual(points.first { $0.deviceId == "192.168.1.10" }?.hashrate, 200)
    }

    func testStaleWindowDoesNotReplayMoveAfterAnotherMinerUsesOldAddress() async throws {
        let suiteName = "DeviceListViewModelTests.staleWindow.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let staleWindowDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        var first = SavedDevice(
            name: "Miner A",
            ipAddress: "192.168.1.10",
            macAddress: "AA:BB:CC:DD:EE:01"
        )
        var second = SavedDevice(
            name: "Miner B",
            ipAddress: "192.168.1.20",
            macAddress: "AA:BB:CC:DD:EE:02"
        )
        try saveSavedDevices([first, second], in: defaults)
        var dependencies = makeDependencies(responses: [:])
        dependencies.autoRefreshOnLoad = false
        let activeWindow = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        let staleWindow = DeviceListViewModel(
            defaults: staleWindowDefaults,
            dependencies: dependencies
        )

        let modelContainer = try makeInMemoryModelContainer()
        let seedingContext = ModelContext(modelContainer)
        seedingContext.insert(
            HistoricalDataPoint(
                timestamp: Date(timeIntervalSince1970: 100),
                hashrate: 100,
                temperature: 50,
                deviceId: "192.168.1.10"
            )
        )
        seedingContext.insert(
            HistoricalDataPoint(
                timestamp: Date(timeIntervalSince1970: 100),
                hashrate: 200,
                temperature: 51,
                deviceId: "192.168.1.20"
            )
        )
        try seedingContext.save()
        let activeContext = ModelContext(modelContainer)
        let staleContext = ModelContext(modelContainer)
        XCTAssertTrue(activeWindow.configureModelContextIfNeeded(activeContext))
        XCTAssertTrue(staleWindow.configureModelContextIfNeeded(staleContext))

        first.ipAddress = "192.168.1.11"
        try saveSavedDevices([first, second], in: defaults)
        activeWindow.loadDevices()
        for _ in 0..<500 {
            if defaults.data(forKey: "pendingHistoryRelocationsV1") == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(defaults.data(forKey: "pendingHistoryRelocationsV1"))

        second.ipAddress = "192.168.1.10"
        try saveSavedDevices([first, second], in: defaults)
        activeWindow.loadDevices()
        for _ in 0..<500 {
            if defaults.data(forKey: "pendingHistoryRelocationsV1") == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(defaults.data(forKey: "pendingHistoryRelocationsV1"))

        staleWindow.loadDevices()
        XCTAssertNil(defaults.data(forKey: "pendingHistoryRelocationsV1"))
        let verifyingContext = ModelContext(modelContainer)
        let points = try verifyingContext.fetch(FetchDescriptor<HistoricalDataPoint>())
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.first { $0.deviceId == "192.168.1.11" }?.hashrate, 100)
        XCTAssertEqual(points.first { $0.deviceId == "192.168.1.10" }?.hashrate, 200)
    }

    func testRapidConsecutiveMovesApplyQueuedHistoryInOrder() async throws {
        let defaults = makeIsolatedDefaults(suiteName: "DeviceListViewModelTests.queuedMoves")
        var savedDevice = SavedDevice(
            name: "Miner A",
            ipAddress: "192.168.1.10",
            macAddress: "AA:BB:CC:DD:EE:01"
        )
        try saveSavedDevices([savedDevice], in: defaults)
        var dependencies = makeDependencies(responses: [:])
        dependencies.autoRefreshOnLoad = false
        let viewModel = DeviceListViewModel(defaults: defaults, dependencies: dependencies)

        let modelContainer = try makeInMemoryModelContainer()
        let seedingContext = ModelContext(modelContainer)
        seedingContext.insert(
            HistoricalDataPoint(
                timestamp: Date(timeIntervalSince1970: 100),
                hashrate: 500,
                temperature: 50,
                deviceId: "192.168.1.10"
            )
        )
        try seedingContext.save()
        XCTAssertTrue(viewModel.configureModelContextIfNeeded(modelContainer.mainContext))

        savedDevice.ipAddress = "192.168.1.11"
        try saveSavedDevices([savedDevice], in: defaults)
        viewModel.loadDevices()
        savedDevice.ipAddress = "192.168.1.12"
        try saveSavedDevices([savedDevice], in: defaults)
        viewModel.loadDevices()

        XCTAssertNotNil(defaults.data(forKey: "pendingHistoryRelocationsV1"))
        for _ in 0..<500 {
            if defaults.data(forKey: "pendingHistoryRelocationsV1") == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNil(defaults.data(forKey: "pendingHistoryRelocationsV1"))
        let verifyingContext = ModelContext(modelContainer)
        let points = try verifyingContext.fetch(FetchDescriptor<HistoricalDataPoint>())
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.deviceId, "192.168.1.12")
        XCTAssertEqual(points.first?.hashrate, 500)
    }

    func testRelocationScanIsThrottledWhileMinerStaysMissing() async {
        actor ScanLog {
            private(set) var count = 0
            func record() { count += 1 }
        }
        let scanLog = ScanLog()
        var dependencies = makeDependencies(responses: [:])
        dependencies.autoRefreshOnLoad = false
        dependencies.relocationScanMinimumInterval = 60 * 60
        dependencies.deviceManagement.scanLocalNetwork = { _ in
            await scanLog.record()
            return []
        }
        let defaults = makeIsolatedDefaults(suiteName: "DeviceListViewModelTests.throttle")
        let viewModel = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        viewModel.savedDevices = [
            SavedDevice(name: "Miner A", ipAddress: "192.168.1.10", macAddress: "AA:BB:CC:DD:EE:01")
        ]

        await viewModel.updateAggregatedStats()
        await viewModel.updateAggregatedStats()

        let scanCount = await scanLog.count
        XCTAssertEqual(scanCount, 1)
    }

    func testNoRelocationScanWhenMissingMinersHaveNoMACAddress() async {
        actor ScanLog {
            private(set) var count = 0
            func record() { count += 1 }
        }
        let scanLog = ScanLog()
        var dependencies = makeDependencies(responses: [:])
        dependencies.autoRefreshOnLoad = false
        dependencies.deviceManagement.scanLocalNetwork = { _ in
            await scanLog.record()
            return []
        }
        let defaults = makeIsolatedDefaults(suiteName: "DeviceListViewModelTests.noIdentity")
        let viewModel = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        viewModel.savedDevices = [SavedDevice(name: "Miner B", ipAddress: "192.168.1.11")]

        await viewModel.updateAggregatedStats()

        let scanCount = await scanLog.count
        XCTAssertEqual(scanCount, 0)
    }

    func testFleetHealthInitialLoadStaysLoadingUntilFirstRefreshCompletes() async {
        var dependencies = makeDependencies(responses: [:])
        dependencies.autoRefreshOnLoad = false

        let defaults = makeIsolatedDefaults(
            suiteName: "DeviceListViewModelTests.fleetHealthLoading"
        )
        let viewModel = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        viewModel.savedDevices = [
            SavedDevice(name: "Miner A", ipAddress: "192.168.1.40"),
            SavedDevice(name: "Miner B", ipAddress: "192.168.1.41"),
        ]
        viewModel.deviceMetrics = [:]

        XCTAssertTrue(viewModel.isFleetHealthLoading)

        await viewModel.updateAggregatedStats()

        XCTAssertFalse(viewModel.isFleetHealthLoading)
        XCTAssertEqual(viewModel.fleetHealthSnapshot.offline, 2)
    }

    func testFleetHealthInitialLoadRedactsCachedMetricsUntilFirstRefreshCompletes() async {
        let responses: [String: DiscoveredDevice] = [
            "192.168.1.50": makeDiscoveredDevice(
                ip: "192.168.1.50",
                name: "Miner A",
                hashrate: 600,
                power: 12,
                bestDiff: "3 M"
            )
        ]
        var dependencies = makeDependencies(responses: responses)
        dependencies.autoRefreshOnLoad = false

        let defaults = makeIsolatedDefaults(suiteName: "DeviceListViewModelTests.fleetHealthCached")
        let viewModel = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        viewModel.savedDevices = [
            SavedDevice(name: "Miner A", ipAddress: "192.168.1.50")
        ]
        viewModel.deviceMetrics = [
            "192.168.1.50": DeviceMetrics(hashrate: 600, temperature: 60)
        ]

        XCTAssertTrue(viewModel.isFleetHealthLoading)

        await viewModel.updateAggregatedStats()

        XCTAssertFalse(viewModel.isFleetHealthLoading)
        XCTAssertEqual(viewModel.fleetHealthSnapshot.online, 1)
    }

    func testFleetHealthInitialLoadUsesMatchingCachedSnapshotDuringRefresh() async throws {
        let responses: [String: DiscoveredDevice] = [
            "192.168.1.60": makeDiscoveredDevice(
                ip: "192.168.1.60",
                name: "Miner A",
                hashrate: 600,
                power: 12,
                bestDiff: "3 M"
            )
        ]
        var dependencies = makeDependencies(responses: responses)
        dependencies.autoRefreshOnLoad = false

        let devices = [
            SavedDevice(name: "Miner A", ipAddress: "192.168.1.60"),
            SavedDevice(name: "Miner B", ipAddress: "192.168.1.61"),
        ]
        let defaults = makeIsolatedDefaults(suiteName: "DeviceListViewModelTests.cachedFleetHealth")
        try saveSavedDevices(devices, in: defaults)

        let cachedSnapshot = FleetHealthSnapshot(
            totalMiners: 2,
            online: 2,
            paused: 0,
            offline: 0,
            unknown: 0,
            zeroHashrate: 0,
            highTemperature: 0
        )
        try saveCachedFleetHealthSnapshot(cachedSnapshot, devices: devices, in: defaults)

        let viewModel = DeviceListViewModel(defaults: defaults, dependencies: dependencies)

        XCTAssertFalse(viewModel.isFleetHealthLoading)
        XCTAssertTrue(viewModel.isFleetHealthRefreshing)
        XCTAssertEqual(viewModel.fleetHealthSnapshot, cachedSnapshot)

        await viewModel.updateAggregatedStats()

        XCTAssertFalse(viewModel.isFleetHealthRefreshing)
        XCTAssertEqual(viewModel.fleetHealthSnapshot.online, 1)
        XCTAssertEqual(viewModel.fleetHealthSnapshot.offline, 1)

        var reloadDependencies = makeDependencies(responses: [:])
        reloadDependencies.autoRefreshOnLoad = false
        let reloadedViewModel = DeviceListViewModel(
            defaults: defaults,
            dependencies: reloadDependencies
        )

        XCTAssertTrue(reloadedViewModel.isFleetHealthRefreshing)
        XCTAssertEqual(reloadedViewModel.fleetHealthSnapshot.online, 1)
        XCTAssertEqual(reloadedViewModel.fleetHealthSnapshot.offline, 1)
    }

    func testFleetHealthInitialLoadIgnoresCachedSnapshotWhenDeviceSetDoesNotMatch() throws {
        var dependencies = makeDependencies(responses: [:])
        dependencies.autoRefreshOnLoad = false

        let devices = [
            SavedDevice(name: "Miner A", ipAddress: "192.168.1.70"),
            SavedDevice(name: "Miner B", ipAddress: "192.168.1.71"),
        ]
        let defaults = makeIsolatedDefaults(
            suiteName: "DeviceListViewModelTests.mismatchedCachedFleetHealth"
        )
        try saveSavedDevices(devices, in: defaults)

        let cachedSnapshot = FleetHealthSnapshot(
            totalMiners: 1,
            online: 1,
            paused: 0,
            offline: 0,
            unknown: 0,
            zeroHashrate: 0,
            highTemperature: 0
        )
        try saveCachedFleetHealthSnapshot(
            cachedSnapshot,
            deviceIPAddresses: ["192.168.1.99"],
            in: defaults
        )

        let viewModel = DeviceListViewModel(defaults: defaults, dependencies: dependencies)

        XCTAssertTrue(viewModel.isFleetHealthLoading)
        XCTAssertFalse(viewModel.isFleetHealthRefreshing)
        XCTAssertEqual(viewModel.fleetHealthSnapshot.online, 0)
        XCTAssertEqual(viewModel.fleetHealthSnapshot.offline, 2)
    }

    func testDeviceGridSortOptionDefaultsToSavedOrderAndPersistsChanges() {
        var dependencies = makeDependencies(responses: [:])
        dependencies.autoRefreshOnLoad = false

        let defaults = makeIsolatedDefaults(suiteName: "DeviceListViewModelTests.gridSort")
        let viewModel = DeviceListViewModel(defaults: defaults, dependencies: dependencies)

        XCTAssertEqual(viewModel.deviceGridSortOption, .savedOrder)

        viewModel.deviceGridSortOption = .hashrate

        XCTAssertEqual(defaults.string(forKey: "deviceGridSortOption"), "hashrate")

        let reloadedViewModel = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        XCTAssertEqual(reloadedViewModel.deviceGridSortOption, .hashrate)
    }

    func testDeviceGridSortOptionFallsBackToSavedOrderForInvalidStoredValue() {
        var dependencies = makeDependencies(responses: [:])
        dependencies.autoRefreshOnLoad = false

        let defaults = makeIsolatedDefaults(suiteName: "DeviceListViewModelTests.invalidGridSort")
        defaults.set("unknown", forKey: "deviceGridSortOption")

        let viewModel = DeviceListViewModel(defaults: defaults, dependencies: dependencies)

        XCTAssertEqual(viewModel.deviceGridSortOption, .savedOrder)
    }

    func testDeleteDevicesWithIPAddressesRemovesMatchingDevicesAndMetrics() {
        var dependencies = makeDependencies(responses: [:])
        dependencies.autoRefreshOnLoad = false

        let defaults = makeIsolatedDefaults(suiteName: "DeviceListViewModelTests.deleteByIP")
        let viewModel = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        viewModel.savedDevices = [
            SavedDevice(name: "Miner A", ipAddress: "192.168.1.10"),
            SavedDevice(name: "Miner B", ipAddress: "192.168.1.11"),
            SavedDevice(name: "Miner C", ipAddress: "192.168.1.12"),
        ]
        viewModel.deviceMetrics = [
            "192.168.1.10": DeviceMetrics(hashrate: 100),
            "192.168.1.11": DeviceMetrics(hashrate: 200),
            "192.168.1.12": DeviceMetrics(hashrate: 300),
        ]

        viewModel.deleteDevices(withIPAddresses: Set(["192.168.1.11"]))

        XCTAssertEqual(
            viewModel.savedDevices.map(\.ipAddress),
            ["192.168.1.10", "192.168.1.12"]
        )
        XCTAssertNil(viewModel.deviceMetrics["192.168.1.11"])
        XCTAssertEqual(viewModel.totalHashRate, 400, accuracy: 0.001)
    }

    func testUpdateAggregatedStatsPersistsHistoricalSamplesWhenModelContextConfigured() async throws
    {
        let responses: [String: DiscoveredDevice] = [
            "192.168.1.30": makeDiscoveredDevice(
                ip: "192.168.1.30",
                name: "Miner A",
                hashrate: 1000,
                power: 20,
                bestDiff: "5 M"
            ),
            "192.168.1.31": makeDiscoveredDevice(
                ip: "192.168.1.31",
                name: "Miner B",
                hashrate: 800,
                power: 16,
                bestDiff: "7 M"
            ),
        ]

        var dependencies = makeDependencies(responses: responses)
        dependencies.autoRefreshOnLoad = false

        let defaults = makeIsolatedDefaults(suiteName: "DeviceListViewModelTests.history")
        let viewModel = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        let modelContainer = try makeInMemoryModelContainer()

        XCTAssertTrue(viewModel.configureModelContextIfNeeded(modelContainer.mainContext))

        viewModel.savedDevices = [
            SavedDevice(name: "Miner A", ipAddress: "192.168.1.30"),
            SavedDevice(name: "Miner B", ipAddress: "192.168.1.31"),
        ]
        viewModel.deviceMetrics = [:]

        await viewModel.updateAggregatedStats()

        let descriptor = FetchDescriptor<HistoricalDataPoint>(
            sortBy: [SortDescriptor(\.deviceId), SortDescriptor(\.timestamp)]
        )
        let rows = try modelContainer.mainContext.fetch(descriptor)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.compactMap(\.deviceId), ["192.168.1.30", "192.168.1.31"])
        XCTAssertEqual(rows.map(\.hashrate), [1000, 800])
    }

    private func makeDependencies(responses: [String: DiscoveredDevice])
        -> DeviceListViewModel.Dependencies
    {
        DeviceListViewModel.Dependencies(
            deviceManagement: .init(
                checkDevice: { ip in
                    guard let device = responses[ip] else {
                        throw DeviceCheckError.requestFailed(.timedOut)
                    }
                    return device
                },
                deleteDevice: { _ in },
                reorderDevices: { _ in }
            ),
            reloadWidget: {},
            autoRefreshOnLoad: true
        )
    }

    private func makeIsolatedDefaults(suiteName: String) -> UserDefaults {
        let uniqueSuiteName = "\(suiteName).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: uniqueSuiteName) else {
            fatalError("Failed to create isolated defaults suite: \(uniqueSuiteName)")
        }
        defaults.removePersistentDomain(forName: uniqueSuiteName)
        return defaults
    }

    private func saveSavedDevices(_ devices: [SavedDevice], in defaults: UserDefaults) throws {
        let data = try JSONEncoder().encode(devices)
        defaults.set(data, forKey: "savedDevices")
    }

    private func saveCachedFleetHealthSnapshot(
        _ snapshot: FleetHealthSnapshot,
        devices: [SavedDevice],
        in defaults: UserDefaults
    ) throws {
        try saveCachedFleetHealthSnapshot(
            snapshot,
            deviceIPAddresses: devices.map(\.ipAddress).sorted(),
            in: defaults
        )
    }

    private func saveCachedFleetHealthSnapshot(
        _ snapshot: FleetHealthSnapshot,
        deviceIPAddresses: [String],
        in defaults: UserDefaults
    ) throws {
        let entry = CachedFleetHealthFixture(
            snapshot: snapshot,
            generatedAt: Date(),
            deviceIPAddresses: deviceIPAddresses
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults.set(try encoder.encode(entry), forKey: "cachedFleetHealthSnapshotV1")
    }

    private func makeInMemoryModelContainer() throws -> ModelContainer {
        let schema = Schema([HistoricalDataPoint.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeDiscoveredDevice(
        ip: String,
        name: String,
        hashrate: Double,
        power: Double,
        bestDiff: String
    ) -> DiscoveredDevice {
        DiscoveredDevice(
            ip: ip,
            name: name,
            hashrate: hashrate,
            temperature: 45,
            bestDiff: bestDiff,
            power: power,
            poolURL: "stratum+tcp://pool.example.com",
            blockHeight: 1,
            networkDifficulty: 2
        )
    }

    private struct CachedFleetHealthFixture: Codable {
        let snapshot: FleetHealthSnapshot
        let generatedAt: Date
        let deviceIPAddresses: [String]
    }
}
