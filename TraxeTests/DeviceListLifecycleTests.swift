import Foundation
import XCTest

@testable import Traxe

@MainActor
final class DeviceListLifecycleTests: XCTestCase {
    func testInitializationDoesNotStartNetworkOrWidgetWork() async throws {
        let suite = "DeviceListLifecycleTests.init.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            try JSONEncoder().encode([SavedDevice(name: "Miner", ipAddress: "192.168.1.10")]),
            forKey: "savedDevices"
        )
        let network = expectation(description: "No initializer network work")
        network.isInverted = true
        let widget = expectation(description: "No initializer widget work")
        widget.isInverted = true
        let dependencies = DeviceListViewModel.Dependencies(
            deviceManagement: .init(
                checkDevice: { _ in
                    network.fulfill()
                    throw URLError(.cannotConnectToHost)
                },
                deleteDevice: { _ in },
                reorderDevices: { _ in }
            ),
            reloadWidget: { widget.fulfill() },
            autoRefreshOnLoad: true
        )
        let first = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        let second = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        XCTAssertEqual(first.savedDevices.count, 1)
        XCTAssertEqual(second.savedDevices.count, 1)
        await fulfillment(of: [network, widget], timeout: 0.15)
    }

    func testTwoModelsFollowPersistedRelocationAndDeleteByStableIdentity() async throws {
        actor Miner {
            var ip = "192.168.1.77"
            func move(to ip: String) { self.ip = ip }
        }
        let miner = Miner()
        let suite = "DeviceListLifecycleTests.relocation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let previousDefaults = DeviceManagementService.sharedDefaultsOverride
        let previousReload = DeviceManagementService.reloadWidgetTimelines
        DeviceManagementService.sharedDefaultsOverride = defaults
        DeviceManagementService.reloadWidgetTimelines = { _ in }
        defer {
            DeviceManagementService.sharedDefaultsOverride = previousDefaults
            DeviceManagementService.reloadWidgetTimelines = previousReload
            defaults.removePersistentDomain(forName: suite)
        }
        let original = SavedDevice(
            name: "Miner",
            ipAddress: "192.168.1.10",
            macAddress: "AA:BB:CC:DD:EE:01"
        )
        defaults.set(try JSONEncoder().encode([original]), forKey: "savedDevices")
        let dependencies = DeviceListViewModel.Dependencies(
            deviceManagement: .init(
                checkDevice: { ip in
                    guard ip == (await miner.ip) else { throw URLError(.cannotConnectToHost) }
                    return DiscoveredDevice(
                        ip: ip,
                        name: "Miner",
                        hashrate: 700,
                        temperature: 50,
                        bestDiff: "2 M",
                        power: 15,
                        poolURL: nil,
                        blockHeight: nil,
                        networkDifficulty: nil,
                        macAddress: "AA:BB:CC:DD:EE:01"
                    )
                },
                deleteDevice: { try DeviceManagementService.deleteDevice(ipAddressToDelete: $0) },
                reorderDevices: { _ in },
                scanLocalNetwork: { _ in
                    [
                        DiscoveredDevice(
                            ip: await miner.ip,
                            name: "Miner",
                            hashrate: 700,
                            temperature: 50,
                            bestDiff: "2 M",
                            power: 15,
                            poolURL: nil,
                            blockHeight: nil,
                            networkDifficulty: nil,
                            macAddress: "AA:BB:CC:DD:EE:01"
                        )
                    ]
                },
                relocateDevices: { try DeviceManagementService.relocateDevices(matching: $0) }
            ),
            reloadWidget: {},
            autoRefreshOnLoad: false,
            relocationScanMinimumInterval: 0
        )
        let first = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        let second = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        await second.updateAggregatedStats()
        XCTAssertEqual(second.savedDevices.first?.ipAddress, "192.168.1.77")
        XCTAssertEqual(first.savedDevices.first?.ipAddress, "192.168.1.10")

        await first.updateAggregatedStats()
        XCTAssertEqual(first.savedDevices.first?.id, original.id)
        XCTAssertEqual(first.savedDevices.first?.ipAddress, "192.168.1.77")
        XCTAssertEqual(first.reachableIPs, ["192.168.1.77"])
        XCTAssertEqual(first.totalHashRate, 700)

        await miner.move(to: "192.168.1.88")
        await second.updateAggregatedStats()
        XCTAssertEqual(second.savedDevices.first?.ipAddress, "192.168.1.88")
        first.deleteDevices(withIPAddresses: ["192.168.1.77"])
        XCTAssertTrue(first.savedDevices.isEmpty)
        let stored = try JSONDecoder().decode(
            [SavedDevice].self,
            from: XCTUnwrap(defaults.data(forKey: "savedDevices"))
        )
        XCTAssertTrue(stored.isEmpty)
        await first.updateAggregatedStats()
        second.synchronizeSavedDevices()
        XCTAssertTrue(second.savedDevices.isEmpty)
        XCTAssertTrue(second.deviceMetrics.isEmpty)
        XCTAssertTrue(second.reachableIPs.isEmpty)
        XCTAssertNil(second.fleetMetricSnapshot.totalHashrate)
    }

    func testStaleSelectionCannotDeleteReplacementAtSameAddress() async throws {
        let suite = "DeviceListLifecycleTests.replacement.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            try JSONEncoder().encode([SavedDevice(name: "Original", ipAddress: "192.168.1.10")]),
            forKey: "savedDevices"
        )
        let dependencies = DeviceListViewModel.Dependencies(
            deviceManagement: .init(
                checkDevice: { _ in throw URLError(.cannotConnectToHost) },
                deleteDevice: { _ in XCTFail("The replacement must not be deleted") },
                reorderDevices: { _ in }
            ),
            reloadWidget: {},
            autoRefreshOnLoad: false
        )
        let model = DeviceListViewModel(defaults: defaults, dependencies: dependencies)
        let replacement = SavedDevice(name: "Replacement", ipAddress: "192.168.1.10")
        defaults.set(try JSONEncoder().encode([replacement]), forKey: "savedDevices")
        model.deleteDevices(withIPAddresses: ["192.168.1.10"])
        XCTAssertEqual(model.savedDevices.first?.id, replacement.id)
        await model.updateAggregatedStats()
    }
}
