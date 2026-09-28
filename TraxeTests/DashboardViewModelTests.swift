import Foundation
import SwiftData
import XCTest

@testable import Traxe

@MainActor
final class DashboardViewModelTests: XCTestCase {
    func testFailedReconnectKeepsRetryingUntilRecoveryAndDisconnectStopsIt() async throws {
        actor Requests {
            var count = 0
            func next() -> Int {
                count += 1
                return count
            }
        }
        let requests = Requests()
        let recovered = expectation(description: "A failed reconnect is retried")
        let telemetry = try JSONDecoder().decode(
            MinerTelemetryDTO.self, from: Data(#"{"hostname":"axe","hashRate":750}"#.utf8)
        )
        let container = try ModelContainer(
            for: HistoricalDataPoint.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let viewModel = DashboardViewModel(
            modelContext: container.mainContext,
            dependencies: .init(
                network: .init(fetchMinerTelemetry: { _ in
                    let call = await requests.next()
                    if call == 2 { throw URLError(.cannotConnectToHost) }
                    if call == 3 { recovered.fulfill() }
                    return telemetry
                }),
                selectedDeviceID: { "192.168.1.44" },
                notificationCenter: NotificationCenter(),
                makeNetworkMonitor: nil,
                networkMonitorQueue: .main,
                sleep: { duration in try? await Task.sleep(for: duration) },
                pollingInterval: .milliseconds(100)
            )
        )
        await viewModel.connect()
        await viewModel.connect()
        if case .disconnected = viewModel.connectionState {
        } else {
            XCTFail("The reconnect must fail before recovery")
        }
        await fulfillment(of: [recovered], timeout: 2)
        let deadline = Date().addingTimeInterval(1)
        while viewModel.connectionState != .connected, Date() < deadline {
            await Task.yield()
        }
        XCTAssertEqual(viewModel.currentMetrics.hashrate, 750)
        XCTAssertEqual(viewModel.connectionState, .connected)
        viewModel.disconnect()
        let countAtDisconnect = await requests.count
        try await Task.sleep(for: .milliseconds(150))
        let countAfterDisconnect = await requests.count
        XCTAssertEqual(countAfterDisconnect, countAtDisconnect)
    }

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

    func testPollingRecoversAfterTransientFailureAndStopsOnDisconnect() async throws {
        actor FetchCounter {
            var count = 0
            func next() -> Int {
                count += 1
                return count
            }
        }
        let counter = FetchCounter()
        let telemetry = try JSONDecoder().decode(
            MinerTelemetryDTO.self,
            from: Data(#"{"hostname":"axe","hashRate":1250}"#.utf8)
        )
        let container = try ModelContainer(
            for: HistoricalDataPoint.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let viewModel = DashboardViewModel(
            modelContext: container.mainContext,
            dependencies: .init(
                network: .init(fetchMinerTelemetry: { _ in
                    if await counter.next() == 2 { throw URLError(.timedOut) }
                    return telemetry
                }),
                selectedDeviceID: { "192.168.1.44" },
                notificationCenter: NotificationCenter(),
                makeNetworkMonitor: nil,
                networkMonitorQueue: .main,
                sleep: { duration in try? await Task.sleep(for: duration) },
                pollingInterval: .milliseconds(5)
            )
        )
        await viewModel.connect()
        let deadline = Date().addingTimeInterval(2)
        while !viewModel.initialFetchComplete && Date() < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(viewModel.initialFetchComplete)
        XCTAssertEqual(viewModel.currentMetrics.hashrate, 1250)
        XCTAssertEqual(viewModel.errorMessage, "")
        if case .connected = viewModel.connectionState {
        } else {
            XCTFail("Polling should reconnect after a transient failure")
        }
        viewModel.disconnect()
        let callsAtDisconnect = await counter.count
        try await Task.sleep(for: .milliseconds(30))
        let callsAfterDisconnect = await counter.count
        XCTAssertEqual(callsAfterDisconnect, callsAtDisconnect)
    }

    func testPollingKeepsTheLastMetricsThroughOneFailedPollAndDisconnectsAfterTwo()
        async throws
    {
        actor FetchSequence {
            private var count = 0
            private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
            private var released: Set<Int> = []
            func next() -> Int {
                count += 1
                return count
            }
            func hold(call: Int) async {
                guard !released.contains(call) else { return }
                await withCheckedContinuation { waiters[call] = $0 }
            }
            func release(call: Int) {
                released.insert(call)
                waiters.removeValue(forKey: call)?.resume()
            }
        }
        let sequence = FetchSequence()
        let thirdFetchStarted = expectation(description: "The third fetch started")
        let fourthFetchStarted = expectation(description: "The fourth fetch started")
        let telemetry = try JSONDecoder().decode(
            MinerTelemetryDTO.self,
            from: Data(#"{"hostname":"axe","hashRate":1250}"#.utf8)
        )
        let recoveredTelemetry = try JSONDecoder().decode(
            MinerTelemetryDTO.self,
            from: Data(#"{"hostname":"axe","hashRate":1500}"#.utf8)
        )
        let container = try ModelContainer(
            for: HistoricalDataPoint.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let viewModel = DashboardViewModel(
            modelContext: container.mainContext,
            dependencies: .init(
                network: .init(fetchMinerTelemetry: { _ in
                    // 1: connect. 2: one dropped request. 3: a second failure in a row, held
                    // until the test has checked the state after the first one. 4 and later:
                    // recovery, held the same way.
                    switch await sequence.next() {
                    case 1:
                        return telemetry
                    case 2:
                        throw URLError(.timedOut)
                    case 3:
                        thirdFetchStarted.fulfill()
                        await sequence.hold(call: 3)
                        throw URLError(.timedOut)
                    case 4:
                        fourthFetchStarted.fulfill()
                        await sequence.hold(call: 4)
                        return recoveredTelemetry
                    default:
                        return recoveredTelemetry
                    }
                }),
                selectedDeviceID: { "192.168.1.44" },
                notificationCenter: NotificationCenter(),
                makeNetworkMonitor: nil,
                networkMonitorQueue: .main,
                sleep: { duration in try? await Task.sleep(for: duration) },
                pollingInterval: .milliseconds(5)
            )
        )
        await viewModel.connect()
        XCTAssertEqual(viewModel.connectionState, .connected)

        // The third fetch only starts after the second one's failure was handled.
        await fulfillment(of: [thirdFetchStarted], timeout: 2)
        XCTAssertEqual(
            viewModel.connectionState, .connected,
            "One failed poll keeps the last metrics on screen"
        )
        XCTAssertEqual(viewModel.currentMetrics.hashrate, 1250)
        XCTAssertEqual(viewModel.errorMessage, "")

        await sequence.release(call: 3)
        await fulfillment(of: [fourthFetchStarted], timeout: 2)
        XCTAssertEqual(
            viewModel.connectionState, .disconnected,
            "Two failed polls in a row disconnect the miner"
        )
        XCTAssertEqual(viewModel.currentMetrics.hashrate, 1250)
        XCTAssertFalse(viewModel.errorMessage.isEmpty)

        await sequence.release(call: 4)
        let deadline = Date().addingTimeInterval(2)
        while viewModel.connectionState != .connected, Date() < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(viewModel.connectionState, .connected)
        XCTAssertEqual(viewModel.currentMetrics.hashrate, 1500)
        XCTAssertEqual(viewModel.errorMessage, "")
        viewModel.disconnect()
    }

    func testDisconnectDiscardsAResponseFromAnInFlightPoll() async throws {
        actor FetchState {
            var count = 0
            var releaseResponse = false
            func next() -> Int {
                count += 1
                return count
            }
            func release() { releaseResponse = true }
        }
        let state = FetchState()
        let initial = try JSONDecoder().decode(
            MinerTelemetryDTO.self,
            from: Data(#"{"hostname":"axe","hashRate":100}"#.utf8)
        )
        let late = try JSONDecoder().decode(
            MinerTelemetryDTO.self,
            from: Data(#"{"hostname":"axe","hashRate":999}"#.utf8)
        )
        let container = try ModelContainer(
            for: HistoricalDataPoint.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let viewModel = DashboardViewModel(
            modelContext: container.mainContext,
            dependencies: .init(
                network: .init(fetchMinerTelemetry: { _ in
                    if await state.next() == 1 { return initial }
                    while !(await state.releaseResponse) { await Task.yield() }
                    return late
                }),
                selectedDeviceID: { "192.168.1.44" },
                notificationCenter: NotificationCenter(),
                makeNetworkMonitor: nil,
                networkMonitorQueue: .main,
                sleep: { duration in try? await Task.sleep(for: duration) },
                pollingInterval: .milliseconds(5)
            )
        )
        await viewModel.connect()
        let deadline = Date().addingTimeInterval(2)
        while await state.count < 2 && Date() < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        let callsBeforeDisconnect = await state.count
        XCTAssertEqual(callsBeforeDisconnect, 2)
        viewModel.disconnect()
        await state.release()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(viewModel.currentMetrics.hashrate, 100)
        XCTAssertFalse(viewModel.initialFetchComplete)
        if case .disconnected = viewModel.connectionState {
        } else {
            XCTFail("A late response must not reconnect a disconnected dashboard")
        }
        XCTAssertEqual(
            try container.mainContext.fetchCount(FetchDescriptor<HistoricalDataPoint>()),
            0
        )
    }

    func testSelectingAnotherMinerDiscardsAnOlderConnectionResponse() async throws {
        actor FetchState {
            var oldRequestStarted = false
            var releaseOldResponse = false
            func startOldRequest() { oldRequestStarted = true }
            func release() { releaseOldResponse = true }
        }
        let state = FetchState()
        let suiteName = "DashboardViewModelTests.selection.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("192.168.1.44", forKey: "selected")
        let oldTelemetry = try JSONDecoder().decode(
            MinerTelemetryDTO.self,
            from: Data(#"{"hostname":"old-axe","hashRate":100}"#.utf8)
        )
        let newTelemetry = try JSONDecoder().decode(
            MinerTelemetryDTO.self,
            from: Data(#"{"hostname":"new-axe","hashRate":200}"#.utf8)
        )
        let container = try ModelContainer(
            for: HistoricalDataPoint.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let viewModel = DashboardViewModel(
            modelContext: container.mainContext,
            dependencies: .init(
                network: .init(fetchMinerTelemetry: { ip in
                    guard ip == "192.168.1.44" else { return newTelemetry }
                    await state.startOldRequest()
                    while !(await state.releaseOldResponse) { await Task.yield() }
                    return oldTelemetry
                }),
                selectedDeviceID: {
                    UserDefaults(suiteName: suiteName)?.string(forKey: "selected")
                },
                notificationCenter: NotificationCenter(),
                makeNetworkMonitor: nil,
                networkMonitorQueue: .main,
                sleep: { duration in try? await Task.sleep(for: duration) },
                pollingInterval: .seconds(60)
            )
        )
        let oldConnection = Task { await viewModel.connect() }
        let deadline = Date().addingTimeInterval(2)
        while !(await state.oldRequestStarted) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        defaults.set("192.168.1.45", forKey: "selected")
        await viewModel.connect()
        await state.release()
        await oldConnection.value
        XCTAssertEqual(viewModel.currentMetrics.hashrate, 200)
        XCTAssertEqual(viewModel.currentMetrics.hostname, "new-axe")
        if case .connected = viewModel.connectionState {
        } else {
            XCTFail("The latest selected miner should stay connected")
        }
        viewModel.disconnect()
    }

    private func makeInMemoryModelContainer() throws -> ModelContainer {
        let schema = Schema([HistoricalDataPoint.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    func testLoadHistoricalDataKeepsOnlyTheNewestHundredPointsInChartOrder() throws {
        let modelContainer = try makeInMemoryModelContainer()
        let context = modelContainer.mainContext
        let deviceID = "192.168.1.44"
        let now = Date()
        for index in 0..<130 {
            context.insert(
                HistoricalDataPoint(
                    timestamp: now.addingTimeInterval(TimeInterval(-index * 5)),
                    hashrate: Double(index),
                    temperature: 60,
                    deviceId: deviceID
                )
            )
        }
        for index in 0..<10 {
            context.insert(
                HistoricalDataPoint(
                    timestamp: now.addingTimeInterval(TimeInterval(-index)),
                    hashrate: 9_999,
                    temperature: 60,
                    deviceId: "192.168.1.45"
                )
            )
        }
        try context.save()

        let viewModel = DashboardViewModel(
            modelContext: context,
            dependencies: .init(
                network: .init(fetchMinerTelemetry: { _ in
                    XCTFail("Loading history must not fetch telemetry")
                    throw NetworkError.unknown
                }),
                selectedDeviceID: { deviceID },
                notificationCenter: NotificationCenter(),
                makeNetworkMonitor: nil,
                networkMonitorQueue: .main,
                sleep: { _ in },
                pollingInterval: .seconds(60)
            )
        )
        viewModel.seedPreviewData(deviceId: deviceID, metrics: DeviceMetrics(), historical: [])

        viewModel.loadHistoricalData()

        XCTAssertEqual(viewModel.historicalData.count, 100)
        // The newest 100 of the 130 samples, oldest first: hashrates 99 down to 0.
        XCTAssertEqual(
            viewModel.historicalData.map(\.hashrate),
            (0..<100).reversed().map { Double($0) }
        )
        XCTAssertTrue(viewModel.historicalData.allSatisfy { $0.deviceId == deviceID })
        let timestamps = viewModel.historicalData.map(\.timestamp)
        XCTAssertEqual(timestamps, timestamps.sorted())
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
