import Foundation
import SwiftData
import XCTest

@testable import Traxe

@MainActor
final class DeviceListViewModelTests: XCTestCase {
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
