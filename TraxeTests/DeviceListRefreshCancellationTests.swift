import Foundation
import XCTest

@testable import Traxe

@MainActor
final class DeviceListRefreshCancellationTests: XCTestCase {
    func testForegroundRefreshReplacesCanceledInFlightRefresh() async throws {
        actor Requests {
            var count = 0
            var isReleased = false
            var continuation: CheckedContinuation<Void, Never>?

            func next() -> Int {
                count += 1
                return count
            }

            func waitForRelease() async {
                guard !isReleased else { return }
                await withCheckedContinuation { continuation = $0 }
            }

            func release() {
                isReleased = true
                continuation?.resume()
                continuation = nil
            }
        }
        let requests = Requests()
        let firstRequestStarted = expectation(description: "The original refresh is suspended")
        let foregroundStarted = expectation(description: "The replacement foreground task started")
        let suite = "DeviceListRefreshCancellationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            try JSONEncoder().encode([SavedDevice(name: "Miner", ipAddress: "192.168.1.10")]),
            forKey: "savedDevices"
        )
        let viewModel = DeviceListViewModel(
            defaults: defaults,
            dependencies: .init(
                deviceManagement: .init(
                    checkDevice: { ip in
                        let request = await requests.next()
                        if request == 1 {
                            firstRequestStarted.fulfill()
                            // Simulate a request that completes despite cancellation.
                            await requests.waitForRelease()
                        }
                        return DiscoveredDevice(
                            ip: ip,
                            name: "Miner",
                            hashrate: request == 1 ? 111 : 222,
                            temperature: 50,
                            bestDiff: "2 M",
                            power: 15,
                            poolURL: nil,
                            blockHeight: nil,
                            networkDifficulty: nil
                        )
                    },
                    deleteDevice: { _ in },
                    reorderDevices: { _ in }
                ),
                reloadWidget: {},
                autoRefreshOnLoad: false
            )
        )
        let originalRefresh = Task { await viewModel.updateAggregatedStats() }
        await fulfillment(of: [firstRequestStarted], timeout: 2)
        originalRefresh.cancel()
        let foregroundRefresh = Task {
            foregroundStarted.fulfill()
            await viewModel.updateAggregatedStats()
        }
        await fulfillment(of: [foregroundStarted], timeout: 2)
        await requests.release()
        await originalRefresh.value
        await foregroundRefresh.value

        let requestCount = await requests.count
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(viewModel.totalHashRate, 222)
        XCTAssertEqual(viewModel.deviceMetrics["192.168.1.10"]?.hashrate, 222)
        XCTAssertEqual(viewModel.reachableIPs, ["192.168.1.10"])
        XCTAssertFalse(viewModel.isLoadingAggregatedStats)
    }

    func testExplicitDeviceLoadQueuesRefreshBehindCurrentOperation() async throws {
        actor Requests {
            var count = 0
            var isReleased = false
            var continuation: CheckedContinuation<Void, Never>?

            func next() -> Int {
                count += 1
                return count
            }

            func waitForRelease() async {
                guard !isReleased else { return }
                await withCheckedContinuation { continuation = $0 }
            }

            func release() {
                isReleased = true
                continuation?.resume()
                continuation = nil
            }
        }
        let requests = Requests()
        let firstRequestStarted = expectation(description: "The initial miner request is suspended")
        let newMinerRequested = expectation(
            description: "An explicit load refreshes the added miner"
        )
        let suite = "DeviceListRefreshCancellationTests.followup.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = SavedDevice(name: "Original", ipAddress: "192.168.1.10")
        defaults.set(try JSONEncoder().encode([original]), forKey: "savedDevices")
        let viewModel = DeviceListViewModel(
            defaults: defaults,
            dependencies: .init(
                deviceManagement: .init(
                    checkDevice: { ip in
                        let request = await requests.next()
                        if request == 1 {
                            firstRequestStarted.fulfill()
                            await requests.waitForRelease()
                        }
                        if ip == "192.168.1.20" { newMinerRequested.fulfill() }
                        return DiscoveredDevice(
                            ip: ip,
                            name: "Miner",
                            hashrate: 222,
                            temperature: 50,
                            bestDiff: "2 M",
                            power: 15,
                            poolURL: nil,
                            blockHeight: nil,
                            networkDifficulty: nil
                        )
                    },
                    deleteDevice: { _ in },
                    reorderDevices: { _ in }
                ),
                reloadWidget: {},
                autoRefreshOnLoad: true
            )
        )
        let initialRefresh = Task { await viewModel.updateAggregatedStats() }
        await fulfillment(of: [firstRequestStarted], timeout: 2)
        defaults.set(
            try JSONEncoder().encode([
                original, SavedDevice(name: "Added", ipAddress: "192.168.1.20"),
            ]),
            forKey: "savedDevices"
        )
        viewModel.loadDevices()
        await requests.release()
        await initialRefresh.value
        await fulfillment(of: [newMinerRequested], timeout: 2)
        let deadline = Date().addingTimeInterval(2)
        while !viewModel.reachableIPs.contains("192.168.1.20"), Date() < deadline {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.totalHashRate, 444)
        XCTAssertEqual(viewModel.reachableIPs, ["192.168.1.10", "192.168.1.20"])
        XCTAssertFalse(viewModel.isLoadingAggregatedStats)
    }

}
