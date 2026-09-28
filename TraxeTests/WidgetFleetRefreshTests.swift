import Foundation
import XCTest

@testable import Traxe

@MainActor
final class WidgetFleetRefreshTests: XCTestCase {
    func testAllFailedPollLoadsPartialFleetSavedWhileRequestsWereSuspended() async throws {
        actor Gate {
            var continuations: [CheckedContinuation<Void, Never>] = []
            func wait(started: XCTestExpectation) async {
                await withCheckedContinuation { continuation in
                    continuations.append(continuation)
                    started.fulfill()
                }
            }
            func release() {
                continuations.forEach { $0.resume() }
                continuations.removeAll()
            }
        }
        let gate = Gate()
        let suite = "WidgetFleetRefreshTests.latestCache.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let miners = [
            SavedDevice(name: "A", ipAddress: "192.168.1.10"),
            SavedDevice(name: "B", ipAddress: "192.168.1.11"),
        ]
        defaults.set(try JSONEncoder().encode(miners), forKey: "savedDevices")
        defaults.set(miners.map(\.ipAddress), forKey: "savedDeviceIPs")
        let cache = DeviceMetricsCache(defaults: defaults)
        var first = CachedDeviceMetrics(from: DeviceMetrics(hashrate: 400), isReachable: true)
        var second = CachedDeviceMetrics(from: DeviceMetrics(hashrate: 600), isReachable: true)
        first.isIncludedInLastKnownTotal = true
        second.isIncludedInLastKnownTotal = true
        cache.saveAll([miners[0].ipAddress: first, miners[1].ipAddress: second])
        let initialState = WidgetFleetRefresh<CachedDeviceMetrics>.State(
            ipAddresses: miners.map(\.ipAddress),
            savedDevicesData: defaults.data(forKey: "savedDevices"),
            metricsByIP: cache.loadAll()
        )
        let started = expectation(description: "Both widget requests started")
        started.expectedFulfillmentCount = 2
        let poll = Task {
            await WidgetFleetRefresh<CachedDeviceMetrics>.run(
                initialState: initialState,
                fetch: { _ in
                    await gate.wait(started: started)
                    throw URLError(.cannotConnectToHost)
                },
                loadCurrentState: {
                    .init(
                        ipAddresses: defaults.stringArray(forKey: "savedDeviceIPs") ?? [],
                        savedDevicesData: defaults.data(forKey: "savedDevices"),
                        metricsByIP: cache.loadAll()
                    )
                }
            )
        }
        await fulfillment(of: [started], timeout: 2)
        first.hashrate = 450
        first.lastUpdated = Date()
        second.isReachable = false
        second.isIncludedInLastKnownTotal = false
        cache.saveAll([miners[0].ipAddress: first, miners[1].ipAddress: second])
        await gate.release()
        let result = await poll.value
        XCTAssertTrue(result.responses.isEmpty)
        XCTAssertTrue(result.canApplyResponses)
        XCTAssertEqual(result.state.metricsByIP[miners[0].ipAddress]?.hashrate, 450)
        XCTAssertEqual(result.state.metricsByIP[miners[0].ipAddress]?.isIncludedInLastKnownTotal, true)
        XCTAssertEqual(result.state.metricsByIP[miners[1].ipAddress]?.isIncludedInLastKnownTotal, false)
    }

    func testChangedSavedIdentityDiscardsOldResponsesAndUsesCurrentTopology() async throws {
        actor Gate {
            var continuation: CheckedContinuation<Void, Never>?
            func wait(started: XCTestExpectation) async {
                await withCheckedContinuation { continuation in
                    self.continuation = continuation
                    started.fulfill()
                }
            }
            func release() {
                continuation?.resume()
                continuation = nil
            }
        }
        for replacementIP in ["192.168.1.10", "192.168.1.12"] {
            let gate = Gate()
            let suite = "WidgetFleetRefreshTests.topology.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let original = SavedDevice(name: "Original", ipAddress: "192.168.1.10")
            defaults.set(try JSONEncoder().encode([original]), forKey: "savedDevices")
            defaults.set([original.ipAddress], forKey: "savedDeviceIPs")
            let cache = DeviceMetricsCache(defaults: defaults)
            cache.saveAll([original.ipAddress: CachedDeviceMetrics(from: DeviceMetrics(hashrate: 400))])
            let initialState = WidgetFleetRefresh<CachedDeviceMetrics>.State(
                ipAddresses: [original.ipAddress],
                savedDevicesData: defaults.data(forKey: "savedDevices"),
                metricsByIP: cache.loadAll()
            )
            let started = expectation(description: "Original miner request started")
            let poll = Task {
                await WidgetFleetRefresh<CachedDeviceMetrics>.run(
                    initialState: initialState,
                    fetch: { _ in
                        await gate.wait(started: started)
                        return .init(hashrate: 9000, temperature: 50)
                    },
                    loadCurrentState: {
                        .init(
                            ipAddresses: defaults.stringArray(forKey: "savedDeviceIPs") ?? [],
                            savedDevicesData: defaults.data(forKey: "savedDevices"),
                            metricsByIP: cache.loadAll()
                        )
                    }
                )
            }
            await fulfillment(of: [started], timeout: 2)
            let replacement = SavedDevice(name: "Replacement", ipAddress: replacementIP)
            defaults.set(try JSONEncoder().encode([replacement]), forKey: "savedDevices")
            defaults.set([replacement.ipAddress], forKey: "savedDeviceIPs")
            cache.saveAll([replacement.ipAddress: CachedDeviceMetrics(from: DeviceMetrics(hashrate: 300))])
            await gate.release()
            let result = await poll.value
            XCTAssertTrue(result.responses.isEmpty)
            XCTAssertFalse(result.canApplyResponses)
            XCTAssertEqual(result.state.ipAddresses, [replacementIP])
            XCTAssertEqual(Set(result.state.metricsByIP.keys), [replacementIP])
            XCTAssertEqual(result.state.metricsByIP[replacementIP]?.hashrate, 300)
        }
    }
}
