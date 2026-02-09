import Foundation
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
}
