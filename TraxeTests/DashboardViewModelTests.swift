import Foundation
import SwiftData
import XCTest

@testable import Traxe

@MainActor
final class DashboardViewModelTests: XCTestCase {
    func testConnectWithConfiguredDevicePopulatesMetricsAndConnectedState() async throws {
        let modelContainer = try makeInMemoryModelContainer()
        let info = try Self.makeSystemInfo(hashRate: 1234.0, temp: 51.0, power: 15.0)
        let dependencies = DashboardViewModel.Dependencies(
            network: .init(fetchSystemInfo: { _ in info }),
            selectedDeviceID: { "192.168.1.44" },
            notificationCenter: NotificationCenter(),
            makeNetworkMonitor: nil,
            networkMonitorQueue: DispatchQueue.main,
            sleep: { duration in
                try? await Task.sleep(for: duration)
            },
            pollingInterval: .seconds(60)
        )

        let viewModel = DashboardViewModel(
            modelContext: modelContainer.mainContext,
            dependencies: dependencies
        )

        await viewModel.connect()

        assertConnectionState(viewModel.connectionState, expected: .connected)
        XCTAssertEqual(viewModel.currentMetrics.hashrate, 1234.0, accuracy: 0.001)
        XCTAssertEqual(viewModel.currentMetrics.temperature, 51.0, accuracy: 0.001)
        XCTAssertEqual(viewModel.currentMetrics.power, 15.0, accuracy: 0.001)
        XCTAssertEqual(viewModel.errorMessage, "")

        viewModel.disconnect()
    }

    func testConnectWithoutConfiguredDeviceSetsDisconnectedState() async throws {
        let modelContainer = try makeInMemoryModelContainer()
        let dependencies = DashboardViewModel.Dependencies(
            network: .init(fetchSystemInfo: { _ in
                XCTFail("fetchSystemInfo should not be called without a configured IP")
                throw NetworkError.configurationMissing
            }),
            selectedDeviceID: { nil },
            notificationCenter: NotificationCenter(),
            makeNetworkMonitor: nil,
            networkMonitorQueue: DispatchQueue.main,
            sleep: { _ in },
            pollingInterval: .seconds(60)
        )

        let viewModel = DashboardViewModel(
            modelContext: modelContainer.mainContext,
            dependencies: dependencies
        )

        await viewModel.connect()

        assertConnectionState(viewModel.connectionState, expected: .disconnected)
        XCTAssertEqual(viewModel.errorMessage, "No miner IP address configured")
        XCTAssertFalse(viewModel.showErrorAlert)
    }

    private func makeInMemoryModelContainer() throws -> ModelContainer {
        let schema = Schema([HistoricalDataPoint.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func makeSystemInfo(hashRate: Double, temp: Double, power: Double) throws
        -> SystemInfoDTO
    {
        let payload: [String: Any] = [
            "power": power,
            "temp": temp,
            "hashRate": hashRate,
            "bestDiff": "2 M",
            "hostname": "Test Miner",
            "version": "axeOS-2.0.0",
            "ASICModel": "BM1366",
            "stratumURL": "stratum+tcp://pool.example.com",
            "stratumUser": "miner.worker",
            "stratumPort": 3333,
            "uptimeSeconds": 900,
            "fanspeed": 75,
            "sharesAccepted": 42,
            "sharesRejected": 1,
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(SystemInfoDTO.self, from: data)
    }

    private func assertConnectionState(
        _ actual: ConnectionState,
        expected: ConnectionState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (actual, expected) {
        case (.connected, .connected), (.connecting, .connecting), (.disconnected, .disconnected):
            return
        default:
            XCTFail("Expected connection state \(expected), got \(actual)", file: file, line: line)
        }
    }
}

extension ConnectionState {
    fileprivate var debugDescription: String {
        switch self {
        case .connected:
            return "connected"
        case .connecting:
            return "connecting"
        case .disconnected:
            return "disconnected"
        }
    }
}
