import Combine
import Foundation
import Network
import SwiftData
import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var currentMetrics = DeviceMetrics()
    @Published private(set) var isLoading = false
    @Published var showErrorAlert = false
    @Published var errorMessage = ""
    @Published private(set) var historicalData: [HistoricalDataPoint] = []
    @Published private(set) var connectionState: ConnectionState = .connecting

    var formattedSharesAccepted: String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        return numberFormatter.string(from: NSNumber(value: currentMetrics.sharesAccepted))
            ?? "\(currentMetrics.sharesAccepted)"
    }

    var formattedHashRate: String {
        currentMetrics.hashrate.formatted(fractionDigits: 2)
    }

    var uptime: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated

        let timeInterval = max(0, currentMetrics.uptime)

        return formatter.string(from: TimeInterval(timeInterval)) ?? "0m"
    }

    var formattedBestDifficulty: (value: String, unit: String) {
        let valueM = currentMetrics.bestDifficulty

        if valueM == 0 {
            return (value: "0", unit: "M")
        }

        let tera = 1_000_000.0
        let giga = 1_000.0
        let kilo = 0.001

        var displayValue: Double
        var unit: String

        if abs(valueM) >= tera {
            displayValue = valueM / tera
            unit = "T"
        } else if abs(valueM) >= giga {
            displayValue = valueM / giga
            unit = "G"
        } else if abs(valueM) >= 1.0 {
            displayValue = valueM
            unit = "M"
        } else if abs(valueM) >= kilo {
            displayValue = valueM / kilo
            unit = "K"
        } else {
            displayValue = valueM
            unit = "M"
        }

        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        if unit == "T" || unit == "G" {
            numberFormatter.maximumFractionDigits = 2
        } else if unit == "M" {
            if abs(valueM) >= 1.0 || valueM == 0 {
                numberFormatter.maximumFractionDigits = 1
                if displayValue.truncatingRemainder(dividingBy: 1) == 0 {
                    numberFormatter.maximumFractionDigits = 0
                }
            } else {
                numberFormatter.maximumFractionDigits = 3
            }
        } else {
            numberFormatter.maximumFractionDigits = 0
        }
        numberFormatter.minimumFractionDigits = 0

        let formattedValueString =
            numberFormatter.string(from: NSNumber(value: displayValue)) ?? "\(displayValue)"
        return (value: formattedValueString, unit: unit)
    }

    private let networkService: NetworkService
    private let modelContext: ModelContext
    private var pollingTask: Task<Void, Never>?
    private var networkMonitor: NWPathMonitor?

    private var cancellables = Set<AnyCancellable>()
    private(set) var initialFetchComplete = false
    private var isConnecting = false

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

            try? await Task.sleep(nanoseconds: 200_000_000)

            updateMetricsFromSystemInfo(systemInfo)
            await MainActor.run {
                self.initialFetchComplete = true
                self.connectionState = .connected
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
                        if error is CancellationError {
                            throw error
                        }

                        let currentState = await MainActor.run { self.connectionState }
                        if let networkError = error as? NetworkError,
                            case .invalidURL = networkError,
                            currentState == .connected
                        {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            continue
                        } else {
                            handleError(error)
                            await MainActor.run { self.connectionState = .disconnected }
                            return
                        }
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

    @MainActor
    func connectIfNeeded() async {
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
        let bestDiffString = info.bestDiff.trimmingCharacters(in: .whitespacesAndNewlines)
        var rawBestDiffValue: Double = 0.0

        if !bestDiffString.isEmpty {
            let lastChar = bestDiffString.last!
            var numericPartString = bestDiffString
            var multiplier: Double = 1.0

            if lastChar.isLetter {
                numericPartString = String(bestDiffString.dropLast())
                switch lastChar.uppercased() {
                case "K": multiplier = 1_000.0
                case "M": multiplier = 1_000_000.0
                case "G": multiplier = 1_000_000_000.0
                case "T": multiplier = 1_000_000_000_000.0
                case "P": multiplier = 1_000_000_000_000_000.0
                default:
                    numericPartString = bestDiffString
                    multiplier = 1.0
                }
            }

            if let numericValue = Double(numericPartString) {
                rawBestDiffValue = numericValue * multiplier
            } else {
            }
        } else {
        }

        let bestDiffValueInM = rawBestDiffValue / 1_000_000.0

        let metrics = DeviceMetrics(
              hashrate: info.hashrate ?? 0.0,
              temperature: info.temperature ?? 0.0,
              power: info.power ?? 0.0,
              uptime: TimeInterval(info.uptime ?? 0),
              fanSpeedPercent: info.fanPercent ?? 0,
              bestDifficulty: bestDiffValueInM,
              inputVoltage: (info.voltage ?? 0.0) / 1000.0,
              asicVoltage: Double(info.coreVoltage ?? 0) / 1000.0,
              measuredVoltage: Double(info.coreVoltageActual ?? 0) / 1000.0,
              frequency: Double(info.frequency ?? 0),
              sharesAccepted: info.sharesAccepted ?? 0,
              sharesRejected: info.sharesRejected ?? 0
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
        if connectionState == .connecting || isLoading || error is CancellationError {
            return
        }

        let shouldDisconnect = true
        let message: String
        if let networkError = error as? NetworkError {
            message = networkError.localizedDescription
        } else {
            message = error.localizedDescription
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if shouldDisconnect {
                if self.connectionState != .disconnected {
                    self.connectionState = .disconnected
                    self.pollingTask?.cancel()
                }
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
