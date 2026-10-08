import Foundation
import XCTest

@testable import Traxe

@MainActor
final class DeviceListCacheFreshnessTests: XCTestCase {
    func testLearningTwoMACAddressesCannotReloadOldCacheOverFreshResults() async throws {
        @MainActor
        final class DefaultsObserver {
            weak var model: DeviceListViewModel?
            var notificationCount = 0
        }
        let observer = DefaultsObserver()
        let suite = "DeviceListCacheFreshnessTests.macNotifications.\(UUID().uuidString)"
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
        let devices = [
            SavedDevice(name: "Miner A", ipAddress: "192.168.1.10"),
            SavedDevice(name: "Miner B", ipAddress: "192.168.1.11"),
        ]
        defaults.set(try JSONEncoder().encode(devices), forKey: "savedDevices")
        let oldMeasurement = Date().addingTimeInterval(-3600)
        let cache = DeviceMetricsCache(defaults: defaults)
        cache.saveAll([
            "192.168.1.10": CachedDeviceMetrics(
                from: DeviceMetrics(
                    hashrate: 700,
                    temperature: 70,
                    power: 17,
                    timestamp: oldMeasurement
                )
            ),
            "192.168.1.11": CachedDeviceMetrics(
                from: DeviceMetrics(
                    hashrate: 800,
                    temperature: 80,
                    power: 18,
                    timestamp: oldMeasurement
                )
            ),
        ])
        let model = DeviceListViewModel(
            defaults: defaults,
            dependencies: .init(
                deviceManagement: .init(
                    checkDevice: { ip in
                        let isFirst = ip == "192.168.1.10"
                        return DiscoveredDevice(
                            ip: ip,
                            name: isFirst ? "Miner A" : "Miner B",
                            hashrate: isFirst ? 111 : 222,
                            temperature: isFirst ? 50 : 60,
                            bestDiff: "2 M",
                            power: isFirst ? 11 : 22,
                            poolURL: nil,
                            blockHeight: nil,
                            networkDifficulty: nil,
                            macAddress: isFirst ? "AA:BB:CC:DD:EE:01" : "AA:BB:CC:DD:EE:02"
                        )
                    },
                    deleteDevice: { _ in },
                    reorderDevices: { _ in },
                    recordMACAddress: { macAddress, ipAddress in
                        try DeviceManagementService.recordMACAddress(
                            macAddress,
                            forDeviceAt: ipAddress
                        )
                        // Deterministically exercise a synchronous defaults observer,
                        // regardless of the OS notification delivery schedule.
                        MainActor.assumeIsolated {
                            observer.notificationCount += 1
                            observer.model?.synchronizeSavedDevices()
                        }
                    }
                ),
                reloadWidget: {},
                autoRefreshOnLoad: false
            )
        )
        observer.model = model
        await model.updateAggregatedStats()

        XCTAssertEqual(observer.notificationCount, 2)
        XCTAssertEqual(model.deviceMetrics["192.168.1.10"]?.hashrate, 111)
        XCTAssertEqual(model.deviceMetrics["192.168.1.11"]?.hashrate, 222)
        XCTAssertEqual(model.deviceMetrics["192.168.1.10"]?.temperature, 50)
        XCTAssertEqual(model.deviceMetrics["192.168.1.11"]?.temperature, 60)
        XCTAssertEqual(model.totalHashRate, 333)
        XCTAssertEqual(model.totalPower, 33)
        XCTAssertEqual(model.fleetMetricSnapshot.totalHashrate, 333)
        XCTAssertEqual(model.reachableIPs, Set(devices.map(\.ipAddress)))
        XCTAssertGreaterThan(model.lastDataUpdate, oldMeasurement)
        let savedCache = cache.loadAll()
        XCTAssertEqual(savedCache["192.168.1.10"]?.hashrate, 111)
        XCTAssertEqual(savedCache["192.168.1.11"]?.hashrate, 222)
    }

    func testCacheMergeStillAcceptsNewerMeasurementsForSameMiner() throws {
        let suite = "DeviceListCacheFreshnessTests.newerCache.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = SavedDevice(
            name: "Miner",
            ipAddress: "192.168.1.10",
            macAddress: "AA:BB:CC:DD:EE:01"
        )
        defaults.set(try JSONEncoder().encode([device]), forKey: "savedDevices")
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
        model.deviceMetrics[device.ipAddress] = DeviceMetrics(
            hashrate: 700,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            macAddress: device.macAddress
        )
        let newerMeasurement = Date(timeIntervalSince1970: 1_700_000_060)
        DeviceMetricsCache(defaults: defaults).saveAll([
            device.ipAddress: CachedDeviceMetrics(
                from: DeviceMetrics(
                    hashrate: 800,
                    timestamp: newerMeasurement,
                    macAddress: device.macAddress
                )
            )
        ])
        model.loadCacheAndComputeTotals()
        XCTAssertEqual(model.deviceMetrics[device.ipAddress]?.hashrate, 800)
        XCTAssertEqual(model.deviceMetrics[device.ipAddress]?.timestamp, newerMeasurement)
        XCTAssertEqual(model.fleetMetricSnapshot.totalHashrate, 800)
    }
}
