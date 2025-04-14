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
    @Published var errorDeviceInfo = ""
    @Published private(set) var historicalData: [HistoricalDataPoint] = []
    @Published private(set) var connectionState: ConnectionState = .connecting

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

    private let networkService: NetworkService
    private let modelContext: ModelContext
    private var pollingTask: Task<Void, Never>?
    private var networkMonitor: NWPathMonitor?

    private var cancellables = Set<AnyCancellable>()
    private(set) var initialFetchComplete = false
    private var isConnecting = false
    private var currentDeviceId: String?

    init(
        networkService: NetworkService? = nil,
        modelContext: ModelContext
    ) {
        self.networkService = networkService ?? NetworkService()
        self.modelContext = modelContext
        setupNetworkMonitoring()
        initializeDeviceTracking()
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

        // Check for device changes
        let suiteName = "group.matthewramsden.traxe"
        if let sharedDefaults = UserDefaults(suiteName: suiteName),
            let deviceId = sharedDefaults.string(forKey: "bitaxeIPAddress"),
            deviceId != currentDeviceId
        {
            startDeviceSession(deviceId: deviceId)
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

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func startPollingIfConnected() {
        if connectionState == .connected {
            startPolling()
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
                guard let deviceId = currentDeviceId else {
                    await MainActor.run { historicalData = [] }
                    return
                }

                let startTime = timeRange.dateRange
                let ranges = getDeviceTimeRanges().filter { $0.deviceId == deviceId }

                let descriptor = FetchDescriptor<HistoricalDataPoint>(
                    predicate: #Predicate<HistoricalDataPoint> { $0.timestamp >= startTime },
                    sortBy: [SortDescriptor(\HistoricalDataPoint.timestamp)]
                )
                let allData = try modelContext.fetch(descriptor)

                // Filter by device time ranges
                let filteredData = allData.filter { dataPoint in
                    ranges.contains { range in range.contains(dataPoint.timestamp) }
                }

                await MainActor.run { historicalData = filteredData }
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

            // Remove commas from numeric part before parsing
            let cleanedNumericString = numericPartString.replacingOccurrences(of: ",", with: "")
            if let numericValue = Double(cleanedNumericString) {
                // Convert the raw display value to the actual base value
                // E.g., "4,070,000 T" should become 4.07 (in millions base unit)
                rawBestDiffValue = numericValue / 1_000_000.0 * multiplier
            } else {
            }
        } else {
        }

        let bestDiffValueInM = rawBestDiffValue

        let uptimeFromAPI = info.uptime ?? 0
        let uptimeSecondsFromAPI = info.uptimeSeconds ?? 0
        
        let metrics = DeviceMetrics(
            hashrate: info.hashrate ?? 0.0,
            expectedHashrate: info.expectedHashrate ?? 0.0,
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
        if error is CancellationError {
            return
        }

        // For initial connection errors, we want to process them even if connecting/loading
        let isInitialConnectionError = connectionState == .connecting && !initialFetchComplete

        let shouldDisconnect = true
        let message: String
        var deviceInfo = ""

        if let networkError = error as? NetworkError {
            message = networkError.localizedDescription

            // Extract device info from decoding errors
            if case .decodingError(let decodingError, let jsonData) = networkError,
                let data = jsonData,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {

                // Extract device info
                let deviceModel =
                    json["deviceModel"] as? String ?? json["hostname"] as? String
                    ?? "Unknown Device"
                let version = json["version"] as? String ?? "Unknown Version"
                deviceInfo = "Device: \(deviceModel) \(version)"

                // Don't try to analyze problem fields - it gives false positives
            }
        } else {
            message = error.localizedDescription
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.errorDeviceInfo = deviceInfo
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

    private func initializeDeviceTracking() {
        let suiteName = "group.matthewramsden.traxe"
        guard let sharedDefaults = UserDefaults(suiteName: suiteName),
            let deviceId = sharedDefaults.string(forKey: "bitaxeIPAddress")
        else { return }

        currentDeviceId = deviceId
        startDeviceSession(deviceId: deviceId)
    }

    private func startDeviceSession(deviceId: String) {
        let suiteName = "group.matthewramsden.traxe"
        guard let sharedDefaults = UserDefaults(suiteName: suiteName) else { return }

        // Close current session if different device
        if let currentId = currentDeviceId, currentId != deviceId {
            endCurrentDeviceSession()
        }

        currentDeviceId = deviceId

        // Start new session for this device
        var ranges = getDeviceTimeRanges()
        ranges.append(DeviceTimeRange(deviceId: deviceId, startTime: Date(), endTime: nil))
        saveDeviceTimeRanges(ranges)
    }

    private func endCurrentDeviceSession() {
        guard let deviceId = currentDeviceId else { return }

        var ranges = getDeviceTimeRanges()
        if let lastIndex = ranges.lastIndex(where: { $0.deviceId == deviceId && $0.endTime == nil })
        {
            ranges[lastIndex] = DeviceTimeRange(
                deviceId: deviceId,
                startTime: ranges[lastIndex].startTime,
                endTime: Date()
            )
            saveDeviceTimeRanges(ranges)
        }
    }

    private func getDeviceTimeRanges() -> [DeviceTimeRange] {
        let suiteName = "group.matthewramsden.traxe"
        guard let sharedDefaults = UserDefaults(suiteName: suiteName),
            let data = sharedDefaults.data(forKey: "deviceTimeRanges"),
            let ranges = try? JSONDecoder().decode([DeviceTimeRange].self, from: data)
        else {
            return []
        }
        return ranges
    }

    private func saveDeviceTimeRanges(_ ranges: [DeviceTimeRange]) {
        let suiteName = "group.matthewramsden.traxe"
        guard let sharedDefaults = UserDefaults(suiteName: suiteName),
            let data = try? JSONEncoder().encode(ranges)
        else { return }

        sharedDefaults.set(data, forKey: "deviceTimeRanges")
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
