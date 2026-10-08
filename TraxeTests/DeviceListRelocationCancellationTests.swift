import Foundation
import XCTest

@testable import Traxe

@MainActor
final class DeviceListRelocationCancellationTests: XCTestCase {
    func testCanceledRelocationScanCanRetryAndCompletedScanStillThrottles() async throws {
        actor Scans {
            var count = 0
            var isReleased = false
            var continuation: CheckedContinuation<Void, Never>?

            func scan(started: XCTestExpectation) async {
                count += 1
                guard count == 1, !isReleased else { return }
                await withCheckedContinuation {
                    continuation = $0
                    started.fulfill()
                }
            }

            func release() {
                isReleased = true
                continuation?.resume()
                continuation = nil
            }
        }
        let scans = Scans()
        let started = expectation(description: "The first relocation scan is suspended")
        let suite = "DeviceListRelocationCancellationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            try JSONEncoder().encode([
                SavedDevice(
                    name: "Missing",
                    ipAddress: "192.168.1.10",
                    macAddress: "AA:BB:CC:DD:EE:01"
                )
            ]),
            forKey: "savedDevices"
        )
        let model = DeviceListViewModel(
            defaults: defaults,
            dependencies: .init(
                deviceManagement: .init(
                    checkDevice: { _ in throw URLError(.cannotConnectToHost) },
                    deleteDevice: { _ in },
                    reorderDevices: { _ in },
                    scanLocalNetwork: { _ in
                        await scans.scan(started: started)
                        return []
                    }
                ),
                reloadWidget: {},
                autoRefreshOnLoad: false,
                relocationScanMinimumInterval: 3600
            )
        )
        let canceledRefresh = Task { await model.updateAggregatedStats() }
        await fulfillment(of: [started], timeout: 2)
        canceledRefresh.cancel()
        await scans.release()
        await canceledRefresh.value

        await model.updateAggregatedStats()
        let countAfterRetry = await scans.count
        XCTAssertEqual(countAfterRetry, 2)
        XCTAssertFalse(model.isLoadingAggregatedStats)

        await model.updateAggregatedStats()
        let countAfterCompletedScan = await scans.count
        XCTAssertEqual(countAfterCompletedScan, 2)
    }
}
