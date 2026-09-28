import Combine
import Foundation
import Network
import Observation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class DashboardViewModel {
    struct Dependencies {
        struct NetworkClient {
            var fetchMinerTelemetry:
                @Sendable (_ ipAddressOverride: String?) async throws -> MinerTelemetryDTO

            static func live(networkService: NetworkService) -> Self {
                Self(
                    fetchMinerTelemetry: { ipAddressOverride in
                        try await networkService.fetchMinerTelemetry(
                            ipAddressOverride: ipAddressOverride
                        )
                    }
                )
            }
        }

        var network: NetworkClient
        var selectedDeviceID: @Sendable () -> String?
        var notificationCenter: NotificationCenter
        var makeNetworkMonitor: (@Sendable () -> NWPathMonitor)?
        var networkMonitorQueue: DispatchQueue
        var sleep: @Sendable (_ duration: Duration) async -> Void
        var pollingInterval: Duration

        static func live(networkService: NetworkService) -> Self {
            Self(
                network: .live(networkService: networkService),
                selectedDeviceID: {
                    UserDefaults(suiteName: "group.matthewramsden.traxe")?.string(
                        forKey: "bitaxeIPAddress"
                    )
                },
                notificationCenter: .default,
                makeNetworkMonitor: { NWPathMonitor() },
                networkMonitorQueue: DispatchQueue.global(),
                sleep: { duration in
                    try? await Task.sleep(for: duration)
                },
                pollingInterval: .seconds(5)
            )
        }
    }

    private(set) var currentMetrics = DeviceMetrics()
    var showErrorAlert = false
    var errorMessage = ""
    var errorDeviceInfo = ""
    private(set) var historicalData: [HistoricalDataPoint] = []
    private(set) var connectionState: ConnectionState = .connecting

    var formattedSharesAccepted: String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        return numberFormatter.string(from: NSNumber(value: currentMetrics.sharesAccepted))
            ?? "\(currentMetrics.sharesAccepted)"
    }

    var formattedHashRate: String {
        currentMetrics.hashrate.formattedHashRateWithUnit().value
    }

    var formattedHashRateUnit: String {
        currentMetrics.hashrate.formattedHashRateWithUnit().unit
    }

    var formattedExpectedHashRate: String {
        currentMetrics.expectedHashrate.formattedExpectedHashRateWithUnit().value
    }

    var formattedExpectedHashRateUnit: String {
        currentMetrics.expectedHashrate.formattedExpectedHashRateWithUnit().unit
    }

    var uptime: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated

        let timeInterval = max(0, currentMetrics.uptime)

        let formattedString = formatter.string(from: TimeInterval(timeInterval)) ?? "0m"

        return formattedString
    }

    var formattedBestDifficulty: (value: String, unit: String) {
        currentMetrics.bestDifficulty.formattedDifficulty()
    }

    private let dependencies: Dependencies
    private let modelContext: ModelContext
    private let historicalDataRetentionController: HistoricalDataRetentionController
    private var pollingTask: Task<Void, Never>?
    private var networkMonitor: NWPathMonitor?

    private var cancellables = Set<AnyCancellable>()
    private(set) var initialFetchComplete = false
    private var isConnecting = false
    private var isConnectionRequested = false
    private var currentDeviceId: String?
    private var connectionGeneration = UUID()
    /// Failed polls in a row before a connected miner is shown as disconnected.
    private static let failedPollsBeforeDisconnected = 2

    init(
        networkService: NetworkService? = nil,
        modelContext: ModelContext,
        dependencies: Dependencies? = nil
    ) {
        let resolvedNetworkService = networkService ?? NetworkService()
        self.dependencies = dependencies ?? .live(networkService: resolvedNetworkService)
        self.modelContext = modelContext
        self.historicalDataRetentionController = HistoricalDataRetentionController(
            modelContext: modelContext
        )
        setupNetworkMonitoring()
        initializeDeviceTracking()
    }

    private func setupNetworkMonitoring() {
        guard let monitor = dependencies.makeNetworkMonitor?() else { return }
        networkMonitor = monitor
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                if path.status == .satisfied {
                    if self.connectionState == .disconnected, self.isConnectionRequested {
                        await self.connect()
                    }
                } else {
                    self.connectionState = .disconnected
                }
            }
        }
        networkMonitor?.start(queue: dependencies.networkMonitorQueue)
    }

    private func initializeDeviceTracking() {
        // Subscribe to changes in the selected IP address
        dependencies.notificationCenter.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.handleDeviceChange() }
            }
            .store(in: &cancellables)
    }

    private func handleDeviceChange() async {
        let newDeviceId = dependencies.selectedDeviceID()

        if newDeviceId != currentDeviceId {
            await connect()
        }
    }

    func connect() async {
        let selectedDeviceId = dependencies.selectedDeviceID()
        guard !isConnecting || selectedDeviceId != currentDeviceId else { return }
        let generation = UUID()
        connectionGeneration = generation
        isConnectionRequested = true
        pollingTask?.cancel()
        pollingTask = nil
        isConnecting = true
        connectionState = .connecting
        currentDeviceId = selectedDeviceId
        defer {
            if connectionGeneration == generation {
                isConnecting = false
                if Task.isCancelled {
                    connectionState = .disconnected
                }
            }
        }

        guard let deviceId = currentDeviceId, !deviceId.isEmpty else {
            connectionState = .disconnected
            errorMessage = "No miner IP address configured"
            return
        }

        do {
            let telemetry = try await dependencies.network.fetchMinerTelemetry(deviceId)
            guard !Task.isCancelled, connectionGeneration == generation else { return }
            let metrics = DeviceMetrics(from: telemetry)

            currentMetrics = metrics
            errorMessage = ""
            errorDeviceInfo = ""
            connectionState = .connected
            startPolling(deviceId: deviceId, generation: generation)
        } catch {
            guard !Task.isCancelled, connectionGeneration == generation else { return }
            let (message, deviceInfo) = handleConnectionError(error, deviceId: deviceId)
            connectionState = .disconnected
            errorMessage = message
            errorDeviceInfo = deviceInfo
            showErrorAlert = true
            // A reconnect may replace an existing retry loop while the miner is still
            // rebooting. Keep retrying this generation until it recovers or disconnects.
            startPolling(deviceId: deviceId, generation: generation)
        }
    }

    private func handleConnectionError(_ error: Error, deviceId: String) -> (
        message: String, deviceInfo: String
    ) {
        if case NetworkError.decodingError(let decodeError, let data) = error {
            let details = buildDecodingErrorDetails(
                data: data,
                deviceId: deviceId,
                underlyingError: decodeError
            )
            return details
        } else {
            let message =
                "Failed to connect to miner at \(deviceId). Please check the IP address and network connection."
            let deviceInfo = "Miner: \(deviceId)\nError: \(error.localizedDescription)"
            return (message, deviceInfo)
        }
    }

    // Mirror onboarding-style clarity for decoding failures: tell the user the miner responded
    // with an unexpected data format and include lightweight context. No raw payload is stored.
    private func buildDecodingErrorDetails(
        data: Data?,
        deviceId: String,
        underlyingError: Error
    ) -> (message: String, deviceInfo: String) {
        var deviceModel = "Unknown Miner"
        var firmwareVersion: String = "Unknown Version"
        var problems: [String] = []
        var failingField: String?

        if let decodingError = underlyingError as? DecodingError {
            switch decodingError {
            case .typeMismatch(_, let context),
                .valueNotFound(_, let context),
                .keyNotFound(_, let context),
                .dataCorrupted(let context):
                failingField = context.codingPath.last?.stringValue
            @unknown default:
                failingField = nil
            }
        }

        if let data = data,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            deviceModel =
                json["deviceModel"] as? String
                ?? json["hostname"] as? String
                ?? deviceModel
            firmwareVersion =
                json["version"] as? String
                ?? json["axeOSVersion"] as? String
                ?? firmwareVersion

            // Highlight unknown fields to hint at schema changes
            let expectedFields = Set(SystemInfoDTO.CodingKeys.allCases.map { $0.rawValue })
            let jsonFields = Set(json.keys)
            let extraFields = jsonFields.subtracting(expectedFields)

            if !extraFields.isEmpty {
                let sortedExtra = Array(extraFields.prefix(3)).sorted()
                problems.append(contentsOf: sortedExtra.map { "\($0) (unknown field)" })
                if extraFields.count > 3 {
                    problems.append("+\(extraFields.count - 3) more unknown fields")
                }
            }

            if let failingField, !failingField.isEmpty {
                problems.insert("Decoder failed on field: \(failingField)", at: 0)
            }
        } else if let failingField, !failingField.isEmpty {
            problems.append("Decoder failed on field: \(failingField)")
        }

        let message =
            "Miner data format changed. Traxe needs an update to read this firmware. Metrics may be unavailable until then."

        var deviceInfo =
            "Miner: \(deviceModel) (\(deviceId))\nFirmware: \(firmwareVersion)\nError: \(underlyingError.localizedDescription)"

        if !problems.isEmpty {
            deviceInfo += "\n\nProblem fields: " + problems.joined(separator: ", ")
        }

        return (message, deviceInfo)
    }

    func disconnect() {
        connectionGeneration = UUID()
        isConnectionRequested = false
        isConnecting = false
        connectionState = .disconnected
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func startPolling(deviceId: String, generation: UUID) {
        pollingTask?.cancel()
        pollingTask = Task {
            // A failed sample changes the visible status, but the selected miner still
            // needs polling so it can recover after a reboot or a temporary network error.
            var consecutiveFailures = 0
            while !Task.isCancelled, connectionGeneration == generation {
                await dependencies.sleep(dependencies.pollingInterval)
                guard !Task.isCancelled, connectionGeneration == generation else { return }

                do {
                    let telemetry = try await dependencies.network.fetchMinerTelemetry(deviceId)
                    guard !Task.isCancelled, connectionGeneration == generation else { return }
                    consecutiveFailures = 0
                    let metrics = DeviceMetrics(from: telemetry)
                    currentMetrics = metrics
                    errorMessage = ""
                    errorDeviceInfo = ""
                    connectionState = .connected
                    initialFetchComplete = true
                    saveHistoricalData(metrics: metrics)
                } catch {
                    guard !Task.isCancelled, connectionGeneration == generation else { return }
                    consecutiveFailures += 1
                    // One dropped request on Wi-Fi is common. A connected miner keeps its last
                    // metrics on screen until a second sample in a row fails, the tolerance
                    // `MinerAlertStateMachine` uses before it reports a miner offline. A miner
                    // that has not answered since connecting stays disconnected.
                    if connectionState == .connected,
                        consecutiveFailures < Self.failedPollsBeforeDisconnected
                    {
                        continue
                    }
                    let (message, deviceInfo) = handleConnectionError(error, deviceId: deviceId)
                    errorMessage = message
                    errorDeviceInfo = deviceInfo
                    connectionState = .disconnected
                }
            }
        }
    }

    private func saveHistoricalData(metrics: DeviceMetrics) {
        let dataPoint = HistoricalDataPoint(
            timestamp: Date(),
            hashrate: metrics.hashrate,
            temperature: metrics.temperature,
            deviceId: currentDeviceId
        )
        modelContext.insert(dataPoint)

        let selectedDeviceId = currentDeviceId
        Task { @MainActor in
            do {
                try historicalDataRetentionController.savePendingChanges(
                    pruningIfNeededFor: selectedDeviceId
                )
            } catch {
            }
        }

        // Update in-memory series for the current device so charts refresh immediately
        let device = currentDeviceId
        Task { @MainActor in
            guard device == self.currentDeviceId else { return }
            // Ensure ascending order; append if newer than last, otherwise insert in order
            if let last = self.historicalData.last, last.timestamp <= dataPoint.timestamp {
                self.historicalData.append(dataPoint)
            } else {
                let insertIndex =
                    self.historicalData.firstIndex { $0.timestamp > dataPoint.timestamp }
                    ?? self.historicalData.count
                self.historicalData.insert(dataPoint, at: insertIndex)
            }
            // Keep only the most recent 100 points
            if self.historicalData.count > 100 {
                let overflow = self.historicalData.count - 100
                self.historicalData.removeFirst(overflow)
            }
        }
    }

    func loadHistoricalData() {
        let device = currentDeviceId
        // Newest first with a fetch limit, so a miner that was polled for weeks does not load
        // every stored point only to keep the last 100. Reversed below into chart order.
        var descriptor = FetchDescriptor<HistoricalDataPoint>(
            predicate: #Predicate<HistoricalDataPoint> { $0.deviceId == device },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 100

        do {
            let newestFirst = try modelContext.fetch(descriptor)
            // Ascending chronological order (oldest -> newest) for chart correctness
            historicalData = newestFirst.reversed()
        } catch {
        }
    }

    // Preload a larger window for first-render trend context
    func preloadHistoricalData() {
        let now = Date()
        let dayAgo = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let device = currentDeviceId
        let predicate = #Predicate<HistoricalDataPoint> { data in
            data.timestamp >= dayAgo && data.deviceId == device
        }
        let descriptor = FetchDescriptor<HistoricalDataPoint>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )
        do {
            let points = try modelContext.fetch(descriptor)
            historicalData = points
        } catch {
        }
    }

    #if DEBUG
        // Preview helper: seed internal state without networking
        func seedPreviewData(
            deviceId: String,
            metrics: DeviceMetrics,
            historical: [HistoricalDataPoint]
        ) {
            self.currentDeviceId = deviceId
            self.currentMetrics = metrics
            self.historicalData = historical
            self.connectionState = .connected
            self.initialFetchComplete = true
        }
    #endif
}
