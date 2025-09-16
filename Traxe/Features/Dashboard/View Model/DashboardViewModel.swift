import Combine
import Foundation
import Network
import SwiftData
import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var currentMetrics = DeviceMetrics()
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
                        self.connectionState = .disconnected
                    }
                }
            }
        }
        networkMonitor?.start(queue: DispatchQueue.global())
    }

    private func initializeDeviceTracking() {
        // Subscribe to changes in the selected IP address
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.handleDeviceChange() }
            }
            .store(in: &cancellables)
    }

    private func handleDeviceChange() async {
        let sharedDefaults = UserDefaults(suiteName: "group.matthewramsden.traxe")
        let newDeviceId = sharedDefaults?.string(forKey: "bitaxeIPAddress")

        if newDeviceId != currentDeviceId {
            currentDeviceId = newDeviceId
            await connect()
        }
    }

    func connect() async {
        guard !isConnecting else { return }
        isConnecting = true
        await MainActor.run {
            self.connectionState = .connecting
        }

        let sharedDefaults = UserDefaults(suiteName: "group.matthewramsden.traxe")
        currentDeviceId = sharedDefaults?.string(forKey: "bitaxeIPAddress")

        guard let deviceId = currentDeviceId, !deviceId.isEmpty else {
            await MainActor.run {
                self.connectionState = .disconnected
                self.errorMessage = "No device IP address configured"
            }
            isConnecting = false
            return
        }

        do {
            let info = try await networkService.fetchSystemInfo(ipAddressOverride: deviceId)
            let metrics = DeviceMetrics(from: info)

            await MainActor.run {
                self.currentMetrics = metrics
                self.errorMessage = ""
                self.errorDeviceInfo = ""
                self.connectionState = .connected
                self.startPolling()
            }
        } catch {
            let (message, deviceInfo) = handleConnectionError(error, deviceId: deviceId)
            await MainActor.run {
                self.connectionState = .disconnected
                self.errorMessage = message
                self.errorDeviceInfo = deviceInfo
                self.showErrorAlert = true
            }
        }

        isConnecting = false
    }

    private func handleConnectionError(_ error: Error, deviceId: String) -> (
        message: String, deviceInfo: String
    ) {
        let message =
            "Failed to connect to device at \(deviceId). Please check the IP address and network connection."
        let deviceInfo = "Device: \(deviceId)\nError: \(error.localizedDescription)"
        return (message, deviceInfo)
    }

    func disconnect() {
        connectionState = .disconnected
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled && connectionState == .connected {
                try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5 seconds

                guard !Task.isCancelled else { continue }

                let deviceId = await MainActor.run { self.currentDeviceId }
                guard let deviceId = deviceId, !deviceId.isEmpty else { continue }

                do {
                    let info = try await networkService.fetchSystemInfo(ipAddressOverride: deviceId)
                    let metrics = DeviceMetrics(from: info)

                    await MainActor.run {
                        self.currentMetrics = metrics
                        self.errorMessage = ""
                        self.errorDeviceInfo = ""

                        if !self.initialFetchComplete {
                            self.initialFetchComplete = true
                        }
                    }

                    await storeSystemInfo(info)

                } catch {
                    if !Task.isCancelled {
                        let (message, deviceInfo) = handleConnectionError(error, deviceId: deviceId)
                        await MainActor.run {
                            self.errorMessage = message
                            self.errorDeviceInfo = deviceInfo
                            self.connectionState = .disconnected
                        }
                    }
                }
            }
        }
    }

    private func storeSystemInfo(_ info: SystemInfoDTO) async {
        let metrics = DeviceMetrics(from: info)
        saveHistoricalData(metrics: metrics)
    }

    private func saveHistoricalData(metrics: DeviceMetrics) {
        let dataPoint = HistoricalDataPoint(
            timestamp: Date(),
            hashrate: metrics.hashrate,
            temperature: metrics.temperature,
            deviceId: currentDeviceId
        )
        modelContext.insert(dataPoint)

        Task {
            do {
                try modelContext.save()
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
        let descriptor = FetchDescriptor<HistoricalDataPoint>(
            predicate: #Predicate<HistoricalDataPoint> { $0.deviceId == device },
            // Ascending chronological order (oldest -> newest) for chart correctness
            sortBy: [SortDescriptor(\.timestamp)]
        )

        do {
            let allData = try modelContext.fetch(descriptor)
            // Keep only the most recent 100 while preserving ascending order
            historicalData = Array(allData.suffix(100))
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

    deinit {
        pollingTask?.cancel()
        networkMonitor?.cancel()
    }

#if DEBUG
    // Preview helper: seed internal state without networking
    func seedPreviewData(deviceId: String, metrics: DeviceMetrics, historical: [HistoricalDataPoint]) {
        self.currentDeviceId = deviceId
        self.currentMetrics = metrics
        self.historicalData = historical
        self.connectionState = .connected
        self.initialFetchComplete = true
    }
#endif
}
