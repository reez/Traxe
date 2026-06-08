import Foundation
import SwiftData
import XCTest

@testable import Traxe

@MainActor
final class DashboardViewModelTests: XCTestCase {
    func testConnectWithConfiguredDevicePopulatesMetricsAndConnectedState() async throws {
        let modelContainer = try makeInMemoryModelContainer()
        let telemetry = try Self.makeTelemetry(hashRate: 1234.0, temp: 51.0, power: 15.0)
        let dependencies = DashboardViewModel.Dependencies(
            network: .init(
                fetchMinerTelemetry: { _ in telemetry }
            ),
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
        XCTAssertEqual(viewModel.currentMetrics.expectedHashrate, 1300.0, accuracy: 0.001)
        XCTAssertEqual(viewModel.currentMetrics.temperature, 51.0, accuracy: 0.001)
        XCTAssertEqual(viewModel.currentMetrics.power, 15.0, accuracy: 0.001)
        XCTAssertEqual(viewModel.currentMetrics.asicHashrateMonitors.count, 1)
        XCTAssertEqual(viewModel.currentMetrics.asicHashrateMonitors.first?.domains, [10, 20])
        XCTAssertEqual(viewModel.currentMetrics.asicErrorPercentage ?? 0, 1.42, accuracy: 0.001)
        XCTAssertEqual(viewModel.errorMessage, "")

        viewModel.disconnect()
    }

    func testConnectWithoutConfiguredDeviceSetsDisconnectedState() async throws {
        let modelContainer = try makeInMemoryModelContainer()
        let dependencies = DashboardViewModel.Dependencies(
            network: .init(
                fetchMinerTelemetry: { _ in
                    XCTFail("fetchMinerTelemetry should not be called without a configured IP")
                    throw NetworkError.configurationMissing
                }
            ),
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

    func testConnectWithTelemetryFromPayloadThatBreaksFullSettingsDecodeStaysConnected()
        async throws
    {
        let modelContainer = try makeInMemoryModelContainer()
        let telemetry = try Self.decodeTelemetryFixture(
            named: "poisoned-optional-settings-system-info.json"
        )
        let dependencies = DashboardViewModel.Dependencies(
            network: .init(
                fetchMinerTelemetry: { _ in telemetry }
            ),
            selectedDeviceID: { "192.168.1.55" },
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
        XCTAssertEqual(viewModel.currentMetrics.hashrate, 777.0, accuracy: 0.001)
        XCTAssertEqual(viewModel.currentMetrics.temperature, 49.0, accuracy: 0.001)
        XCTAssertEqual(viewModel.currentMetrics.power, 88.0, accuracy: 0.001)
        XCTAssertEqual(viewModel.currentMetrics.hostname, "future-miner")
        XCTAssertEqual(viewModel.errorMessage, "")

        viewModel.disconnect()
    }

    private static func makeTelemetry(hashRate: Double, temp: Double, power: Double) throws
        -> MinerTelemetryDTO
    {
        let payload: [String: Any] = [
            "power": power,
            "temp": temp,
            "hashRate": hashRate,
            "expectedHashrate": 1300.0,
            "errorPercentage": 1.42,
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
            "hashrateMonitor": [
                "asics": [
                    [
                        "total": hashRate,
                        "domains": [10, 20],
                    ]
                ]
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(MinerTelemetryDTO.self, from: data)
    }

    private static func decodeTelemetryFixture(named filename: String) throws -> MinerTelemetryDTO {
        let data = try fixtureData(named: filename)
        return try JSONDecoder().decode(MinerTelemetryDTO.self, from: data)
    }

    private static func fixtureData(named filename: String) throws -> Data {
        let testFile = URL(fileURLWithPath: #filePath)
        let fixtureURL = testFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent(filename)
        return try Data(contentsOf: fixtureURL)
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
