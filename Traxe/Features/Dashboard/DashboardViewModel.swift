import Combine
import Foundation
import Network
import SwiftData
import SwiftUI

enum TimeRange: String, CaseIterable, Identifiable {
    case lastHour = "1H"
    case lastDay = "24H"
    case lastWeek = "7D"

    var id: String { rawValue }

    var dateRange: Date {
        let now = Date()
        switch self {
        case .lastHour:
            return now.addingTimeInterval(-3600)
        case .lastDay:
            return now.addingTimeInterval(-86400)
        case .lastWeek:
            return now.addingTimeInterval(-604800)
        }
    }
}

enum ConnectionState {
    case disconnected
    case connecting
    case connected
}

@MainActor
final class DashboardViewModel: ObservableObject {
    // MARK: - Published Properties (UI State)
    @Published private(set) var currentMetrics = DeviceMetrics()
    @Published private(set) var isLoading = false
    @Published var showErrorAlert = false
    @Published var errorMessage = ""
    @Published private(set) var historicalData: [HistoricalDataPoint] = []
    @Published private(set) var connectionState: ConnectionState = .connecting

    // MARK: - Dependencies
    private let networkService: NetworkService
    private let modelContext: ModelContext
    private var pollingTask: Task<Void, Never>?
    private var networkMonitor: NWPathMonitor?

    // MARK: - Private State
    private var cancellables = Set<AnyCancellable>()
    private(set) var initialFetchComplete = false
    private var isConnecting = false

    // MARK: - Initialization
    init(
        networkService: NetworkService? = nil,
        modelContext: ModelContext
    ) {
        self.networkService = networkService ?? NetworkService()
        self.modelContext = modelContext
        setupNetworkMonitoring()
    }

    private func setupNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            Task {
                guard let self else { return }
                if path.status == .satisfied {
                    let currentState = await MainActor.run { self.connectionState }
                    if currentState == .disconnected {
                        await self.connect()
                    }
                } else {
                    await MainActor.run {
                        self.pollingTask?.cancel()
                        self.connectionState = .disconnected
                    }
                }
            }
        }
        networkMonitor?.start(queue: DispatchQueue.global(qos: .background))
    }

    func connect() async {
        guard !isConnecting else { return }
        isConnecting = true
        await MainActor.run {
            self.connectionState = .connecting
            self.isLoading = true
        }

        do {
            let systemInfo = try await networkService.fetchSystemInfo()

            // Add delay *after* successful fetch, *before* UI update/polling
            try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2 seconds

            updateMetricsFromSystemInfo(systemInfo)
            await MainActor.run {
                self.initialFetchComplete = true
                self.connectionState = .connected
                // Don't sleep here anymore
                self.startPolling()
            }
        } catch {
            handleError(error)
            await MainActor.run {
                self.connectionState = .disconnected
            }
        }

        await MainActor.run {
            self.isLoading = false
            self.isConnecting = false
        }
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            do {
                while !Task.isCancelled {
                    do {
                        let systemInfo = try await networkService.fetchSystemInfo()
                        updateMetricsFromSystemInfo(systemInfo)
                        fetchHistoricalData(timeRange: .lastHour)
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                    } catch {
                        if error is CancellationError { throw error }

                        // --- New Error Handling Logic ---
                        // Check if it's the specific invalidURL error AND we think we are connected
                        let currentState = await MainActor.run { self.connectionState }
                        if let networkError = error as? NetworkError,
                            case .invalidURL = networkError,
                            currentState == .connected
                        {
                            // Likely the transient UserDefaults sync issue right after connecting.
                            // Log it for debugging, but don't show alert or disconnect.
                            // Add a small delay before the next poll attempt just in case
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            // Continue to the next iteration of the loop
                            continue
                        } else {
                            // Handle all other errors normally (including invalidURL if not connected)
                            handleError(error)
                            await MainActor.run { self.connectionState = .disconnected }
                            return  // Stop polling on other errors
                        }
                        // --- End New Error Handling Logic ---
                    }
                }
            } catch {
                if error is CancellationError {
                    return
                }
                handleError(error)
                await MainActor.run {
                    self.connectionState = .disconnected
                }
            }
        }
    }

    // MARK: - Public Methods
    @MainActor
    func connectIfNeeded() async {
        // Only attempt connection if currently disconnected
        if connectionState == .disconnected {
            await connect()
        }
    }

    func refreshData() async {
        pollingTask?.cancel()
        pollingTask = nil

        await fetchInitialData()
        fetchHistoricalData(timeRange: .lastHour)

        if connectionState == .connected {
            startPolling()
        }
    }

    func fetchHistoricalData(timeRange: TimeRange) {
        Task {
            do {
                let startTime = timeRange.dateRange
                let descriptor = FetchDescriptor<HistoricalDataPoint>(
                    predicate: #Predicate<HistoricalDataPoint> { $0.timestamp >= startTime },
                    sortBy: [SortDescriptor(\HistoricalDataPoint.timestamp)]
                )
                historicalData = try modelContext.fetch(descriptor)
            } catch {
                handleError(error)
            }
        }
    }

    // MARK: - Private Methods
    private func fetchInitialData() async {
        guard !isLoading else { return }

        isLoading = true
        if !initialFetchComplete {
        }

        do {
            let systemInfo = try await networkService.fetchSystemInfo()
            updateMetricsFromSystemInfo(systemInfo)
            initialFetchComplete = true
            if !initialFetchComplete {
            }
        } catch {
            handleError(error)
            if !initialFetchComplete {
                await MainActor.run {
                    self.connectionState = .disconnected
                }
            }
        }

        isLoading = false
    }

    private func updateMetricsFromSystemInfo(_ info: SystemInfoDTO) {
        let bestDiff = info.bestDiff.lowercased()
        let bestDiffValue: Double
        if bestDiff.hasSuffix("m") {
            bestDiffValue = (Double(bestDiff.dropLast()) ?? 0.0)
        } else if bestDiff.hasSuffix("k") {
            bestDiffValue = (Double(bestDiff.dropLast()) ?? 0.0) / 1000.0
        } else {
            bestDiffValue = (Double(bestDiff) ?? 0.0) / 1_000_000.0
        }

        let metrics = DeviceMetrics(
            hashrate: info.hashrate ?? 0.0,
            temperature: info.temperature ?? 0.0,
            power: info.power,
            uptime: TimeInterval(info.uptime ?? 0),
            fanSpeedPercent: info.fanPercent ?? 0,
            bestDifficulty: bestDiffValue,
            inputVoltage: info.voltage / 1000.0,
            asicVoltage: Double(info.coreVoltage) / 1000.0,
            measuredVoltage: Double(info.coreVoltageActual) / 1000.0,
            frequency: Double(info.frequency),
            sharesAccepted: info.sharesAccepted,
            sharesRejected: info.sharesRejected
        )
        currentMetrics = metrics
        saveHistoricalData(metrics: metrics)
    }

    private func saveHistoricalData(metrics: DeviceMetrics) {
        let dataPoint = HistoricalDataPoint(
            timestamp: Date(),
            hashrate: metrics.hashrate,
            temperature: metrics.temperature
        )
        modelContext.insert(dataPoint)

        Task {
            do {
                let oldDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                let descriptor = FetchDescriptor<HistoricalDataPoint>(
                    predicate: #Predicate<HistoricalDataPoint> { $0.timestamp < oldDate }
                )
                let oldPoints = try modelContext.fetch(descriptor)
                oldPoints.forEach { modelContext.delete($0) }
            } catch {

            }
        }
    }

    private func handleError(_ error: Error) {
        if connectionState == .connecting || isLoading {
            return
        }

        let shouldDisconnect = true
        let message: String
        if let networkError = error as? NetworkError {
            message = networkError.localizedDescription
        } else if error is CancellationError {
            return
        } else {
            message = error.localizedDescription
        }

        DispatchQueue.main.async {
            if shouldDisconnect {
                self.connectionState = .disconnected
                self.pollingTask?.cancel()
            }
            self.errorMessage = message
            self.showErrorAlert = true
        }
    }

    deinit {
        pollingTask?.cancel()
        networkMonitor?.cancel()
    }

    func setError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }
}
