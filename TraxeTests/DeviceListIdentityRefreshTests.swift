import Foundation
import XCTest

@testable import Traxe

@MainActor
final class DeviceListIdentityRefreshTests: XCTestCase {
    func testSuspendedResponseCannotAttachToReplacementAtSameIPAddress() async throws {
        actor ResponseGate {
            var continuation: CheckedContinuation<DiscoveredDevice, Never>?
            func wait(started: XCTestExpectation) async -> DiscoveredDevice {
                await withCheckedContinuation {
                    continuation = $0
                    started.fulfill()
                }
            }
            func complete(_ response: DiscoveredDevice) {
                continuation?.resume(returning: response)
                continuation = nil
            }
        }
        for responseMAC in ["AA:BB:CC:DD:EE:01", nil] as [String?] {
            let suite = "DeviceListIdentityRefreshTests.suspended.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let original = SavedDevice(name: "Original", ipAddress: "192.168.1.10")
            defaults.set(try JSONEncoder().encode([original]), forKey: "savedDevices")
            let started = expectation(description: "Original request started")
            let gate = ResponseGate()
            let model = DeviceListViewModel(
                defaults: defaults,
                dependencies: .init(
                    deviceManagement: .init(
                        checkDevice: { _ in
                            await gate.wait(started: started)
                        },
                        deleteDevice: { _ in },
                        reorderDevices: { _ in },
                        recordMACAddress: { _, _ in
                            XCTFail("An old request must not teach the replacement its MAC")
                        }
                    ),
                    reloadWidget: {},
                    autoRefreshOnLoad: false
                )
            )
            let refresh = Task { await model.updateAggregatedStats() }
            await fulfillment(of: [started], timeout: 2)
            let replacement = SavedDevice(name: "Replacement", ipAddress: original.ipAddress)
            defaults.set(try JSONEncoder().encode([replacement]), forKey: "savedDevices")
            await gate.complete(
                DiscoveredDevice(
                    ip: original.ipAddress,
                    name: "Original",
                    hashrate: 700,
                    temperature: 50,
                    bestDiff: "2 M",
                    power: 15,
                    poolURL: nil,
                    blockHeight: nil,
                    networkDifficulty: nil,
                    macAddress: responseMAC
                )
            )
            await refresh.value
            XCTAssertEqual(model.savedDevices.first?.id, replacement.id)
            XCTAssertNil(model.savedDevices.first?.macAddress)
            XCTAssertTrue(model.deviceMetrics.isEmpty)
            XCTAssertTrue(model.reachableIPs.isEmpty)
            XCTAssertNil(model.fleetMetricSnapshot.totalHashrate)
            XCTAssertTrue(DeviceMetricsCache(defaults: defaults).loadAll().isEmpty)
        }
    }

    func testSynchronizingReplacementDropsOldMemoryAndCacheAtReusedAddress() async throws {
        let suite = "DeviceListIdentityRefreshTests.cachedReplacement.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = SavedDevice(
            name: "Original",
            ipAddress: "192.168.1.10",
            macAddress: "AA:BB:CC:DD:EE:01"
        )
        defaults.set(try JSONEncoder().encode([original]), forKey: "savedDevices")
        let model = DeviceListViewModel(
            defaults: defaults,
            dependencies: .init(
                deviceManagement: .init(
                    checkDevice: { ip in
                        DiscoveredDevice(
                            ip: ip,
                            name: "Original",
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
                    deleteDevice: { _ in },
                    reorderDevices: { _ in }
                ),
                reloadWidget: {},
                autoRefreshOnLoad: false
            )
        )
        await model.updateAggregatedStats()
        XCTAssertEqual(model.totalHashRate, 700)
        let replacement = SavedDevice(name: "Replacement", ipAddress: original.ipAddress)
        defaults.set(try JSONEncoder().encode([replacement]), forKey: "savedDevices")
        model.synchronizeSavedDevices()
        XCTAssertEqual(model.savedDevices.first?.id, replacement.id)
        XCTAssertTrue(model.deviceMetrics.isEmpty)
        XCTAssertTrue(model.reachableIPs.isEmpty)
        XCTAssertNil(model.fleetMetricSnapshot.totalHashrate)
        XCTAssertTrue(DeviceMetricsCache(defaults: defaults).loadAll().isEmpty)
    }

    func testInitialCacheLoadRejectsDifferentKnownMinerAtSameAddress() throws {
        let suite = "DeviceListIdentityRefreshTests.cacheMAC.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let replacement = SavedDevice(
            name: "Replacement",
            ipAddress: "192.168.1.10",
            macAddress: "AA:BB:CC:DD:EE:02"
        )
        defaults.set(try JSONEncoder().encode([replacement]), forKey: "savedDevices")
        let cache = DeviceMetricsCache(defaults: defaults)
        cache.saveAll([
            replacement.ipAddress: CachedDeviceMetrics(
                from: DeviceMetrics(hashrate: 700, macAddress: "AA:BB:CC:DD:EE:01"),
                isReachable: true
            )
        ])
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
        XCTAssertTrue(model.deviceMetrics.isEmpty)
        XCTAssertNil(model.fleetMetricSnapshot.totalHashrate)
        XCTAssertTrue(cache.loadAll().isEmpty)
    }
}
