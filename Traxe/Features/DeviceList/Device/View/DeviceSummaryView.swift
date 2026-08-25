import Foundation
import SimpleToast
import SwiftData
import SwiftUI

struct DeviceSummaryView: View {
    private struct AISummaryTaskID: Equatable {
        let deviceIP: String
        let isDataLoaded: Bool
    }

    let dashboardViewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showingSettings = false
    @State private var showingWeeklyRecap = false
    @State private var showBlockFoundToast = false
    @State private var lastBlockFoundValue: Int? = nil
    @State private var settingsViewModel: SettingsViewModel?
    let deviceName: String
    let deviceIP: String
    let poolName: String?
    let onMinerDeleted: (String) -> Void

    @State private var summaryController: DeviceAISummaryController

    init(
        dashboardViewModel: DashboardViewModel,
        deviceName: String,
        deviceIP: String,
        poolName: String?,
        onMinerDeleted: @escaping (String) -> Void = { _ in },
        summaryController: DeviceAISummaryController? = nil
    ) {
        self.dashboardViewModel = dashboardViewModel
        self.deviceName = deviceName
        self.deviceIP = deviceIP
        self.poolName = poolName
        self.onMinerDeleted = onMinerDeleted
        self._summaryController = State(
            initialValue: summaryController ?? DeviceAISummaryController()
        )
    }

    private var displayPoolName: String? { dashboardViewModel.currentMetrics.poolURL ?? poolName }
    private var poolRows: [PoolDisplayLineViewData] {
        PoolDisplayPresenter.makeRows(from: displayPoolName)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.tertiarySystemBackground),
                    Color(.secondarySystemBackground),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 40) {
                    DeviceSummaryHeaderView(
                        deviceName: deviceName,
                        poolRows: poolRows
                    )

                    VStack(alignment: .leading, spacing: 16) {
                        if AIFeatureFlags.isAvailable,
                            AIFeatureFlags.isEnabledByUser
                        {
                            DeviceAISummarySectionView(
                                summary: summaryController.summary,
                                isDataLoaded: dashboardViewModel.connectionState == .connected,
                                historicalData: dashboardViewModel.connectionState == .connected
                                    ? dashboardViewModel.historicalData
                                    : []
                            )
                        }

                        WeeklyRecapNavigationTile(viewData: .device) {
                            showingWeeklyRecap = true
                        }
                    }
                    .padding(.horizontal)

                    if dashboardViewModel.connectionState == .connected,
                        !dashboardViewModel.currentMetrics.asicHashrateMonitors.isEmpty
                    {
                        DeviceSummaryASICHeatmapView(
                            monitors: dashboardViewModel.currentMetrics.asicHashrateMonitors,
                            expectedHashrate: dashboardViewModel.currentMetrics.expectedHashrate,
                            chipTemperature: dashboardViewModel.currentMetrics.temperature,
                            isChipTemperatureKnown: dashboardViewModel.currentMetrics
                                .isTemperatureKnown,
                            vrTemperature: dashboardViewModel.currentMetrics.vrTemperature,
                            isVRTemperatureKnown: dashboardViewModel.currentMetrics
                                .isVRTemperatureKnown,
                            errorPercentage: dashboardViewModel.currentMetrics
                                .asicErrorPercentage
                        )
                        .padding(.horizontal)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Stats")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .padding(.horizontal)

                        MetricsSummaryGrid(viewModel: dashboardViewModel)
                    }

                    if dashboardViewModel.connectionState == .connected {
                        DeviceSummaryNetworkInfoView(
                            blockHeight: dashboardViewModel.currentMetrics.blockHeight,
                            networkDifficulty: dashboardViewModel.currentMetrics.networkDifficulty
                        )
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: summaryController.summary != nil)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .debugBlockFoundToast {
                showBlockFoundToast = true
            }
        }
        .navigationTitle(deviceIP)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    settingsViewModel = SettingsViewModel(
                        sharedUserDefaults: UserDefaults(
                            suiteName: SettingsViewModel.sharedUserDefaultsSuiteName
                        ),
                        modelContext: modelContext
                    )
                    showingSettings = true
                } label: {
                    // The title is what the system shows when the item moves into an
                    // overflow menu or a vertical bar cannot fit the symbol alone.
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .sheet(
            isPresented: $showingSettings,
            onDismiss: {
                settingsViewModel = nil
            }
        ) {
            if let settingsViewModel {
                SettingsView(
                    viewModel: settingsViewModel,
                    onMinerDeleted: handleMinerDeleted
                )
            }
        }
        .onAppear {
            lastBlockFoundValue = dashboardViewModel.currentMetrics.blockFound
        }
        .onChange(of: dashboardViewModel.currentMetrics.blockFound) { _, newValue in
            let previousValue = lastBlockFoundValue
            lastBlockFoundValue = newValue

            guard dashboardViewModel.connectionState == .connected else { return }
            let previousCount = previousValue ?? 0
            let currentCount = newValue ?? 0
            guard currentCount > previousCount else { return }
            showBlockFoundToast = true
        }
        .simpleToast(
            isPresented: $showBlockFoundToast,
            options: .init(
                hideAfter: 5.0,
                animation: .spring,
                modifierType: .slide
            )
        ) {
            BlockFoundToastView(
                blockHeight: dashboardViewModel.currentMetrics.blockHeight,
                poolName: displayPoolName
            )
            .padding(.horizontal, 24)
        }
        .task(id: deviceIP) {
            // Device-list navigation connects before presenting this screen. Starting a
            // second connection here would put the already-populated metrics back into the
            // redacted `.connecting` state while the summary is being prepared.
            guard !ProcessInfo.isPreview,
                dashboardViewModel.connectionState != .connected
            else { return }
            await dashboardViewModel.connect()
        }
        // Generation begins only after the first telemetry fetch. This preserves the
        // original ordering: historical data is loaded first, the summary is generated once,
        // and the completed value then enters the character-by-character reveal.
        .task(
            id: AISummaryTaskID(
                deviceIP: deviceIP,
                isDataLoaded: dashboardViewModel.connectionState == .connected
            )
        ) {
            guard AIFeatureFlags.isAvailable,
                AIFeatureFlags.isEnabledByUser,
                dashboardViewModel.connectionState == .connected
            else { return }

            if !ProcessInfo.isPreview {
                dashboardViewModel.loadHistoricalData()
            }

            await summaryController.loadSummary(
                for: deviceIP,
                historicalData: dashboardViewModel.historicalData
            )
        }
        .navigationDestination(isPresented: $showingWeeklyRecap) {
            WeeklyRecapView(
                scope: .device(
                    deviceID: deviceIP,
                    deviceName: deviceName,
                    poolName: displayPoolName
                )
            )
        }
    }

    private func handleMinerDeleted(_ deletedIPAddress: String) {
        dashboardViewModel.disconnect()
        onMinerDeleted(deletedIPAddress)
        dismiss()
    }
}

extension View {
    @ViewBuilder
    fileprivate func debugBlockFoundToast(_ action: @escaping () -> Void) -> some View {
        #if DEBUG
            self.onTapGesture(count: 3, perform: action)
        #else
            self
        #endif
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = makeDeviceSummaryPreviewContainer(config: config)
    let previewViewModel = DashboardViewModel(modelContext: container.mainContext)

    // Seed current device selection and AI enablement
    let groupDefaults = previewSharedDefaults()
    groupDefaults.set("192.168.1.102", forKey: "bitaxeIPAddress")
    UserDefaults.standard.set(true, forKey: "ai_enabled")
    UserDefaults.standard.set(
        "Over the last 24 hours the miner has averaged 721.0 GH/s. This miner's solo odds to hit a block are 1 in 5.7M today (15.7K yr expected).",
        forKey: "preview_device_summary"
    )

    // Seed live metrics and a simple historical series
    let now = Date()
    var historical: [HistoricalDataPoint] = []
    for i in (0..<30) {  // 30 points at 1‑min intervals
        let t = Calendar.current.date(byAdding: .minute, value: -i, to: now) ?? now
        // Deterministic oscillation around 721.0 GH/s and 66°C
        let deltaHash = (i % 6) - 3  // -3..2
        let deltaTemp = (i % 4) - 2  // -2..1
        let point = HistoricalDataPoint(
            timestamp: t,
            hashrate: 721.0 + Double(deltaHash),
            temperature: 66 + Double(deltaTemp),
            deviceId: "192.168.1.102"
        )
        historical.append(point)
    }
    // ascending order
    historical.sort { $0.timestamp < $1.timestamp }

    let metrics = DeviceMetrics(
        hashrate: 721.0,  // GH/s
        expectedHashrate: 721.0,
        temperature: 66,
        power: 16.1,
        uptime: TimeInterval(27 * 24 * 60 * 60),  // 27 days
        fanSpeedPercent: 82,
        timestamp: now,
        bestDifficulty: 598.7,  // in M
        inputVoltage: 0,
        asicVoltage: 0,
        measuredVoltage: 0,
        frequency: 0,
        sharesAccepted: 985,
        sharesRejected: 0,
        poolURL: "mine.ocean.xyz",
        hostname: "bitaxe",
        blockHeight: 874_321,
        networkDifficulty: 83_250_000_000_000,
        asicHashrateMonitors: previewASICHashrateMonitors(),
        asicErrorPercentage: 1.42,
        vrTemperature: 54,
        isVRTemperatureKnown: true
    )

    #if DEBUG
        previewViewModel.seedPreviewData(
            deviceId: "192.168.1.102",
            metrics: metrics,
            historical: historical
        )
    #endif

    return NavigationStack {
        DeviceSummaryView(
            dashboardViewModel: previewViewModel,
            deviceName: "bitaxe",
            deviceIP: "192.168.1.102",
            poolName: "mine.ocean.xyz"
        )
    }
}

#Preview("Device Summary - Dual Pool") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = makeDeviceSummaryPreviewContainer(config: config)
    let previewViewModel = DashboardViewModel(modelContext: container.mainContext)

    // Seed current device selection and AI enablement
    let groupDefaults = previewSharedDefaults()
    groupDefaults.set("192.168.1.102", forKey: "bitaxeIPAddress")
    UserDefaults.standard.set(true, forKey: "ai_enabled")
    UserDefaults.standard.set(
        "Over the last 24 hours the miner has averaged 721.0 GH/s. This miner's solo odds to hit a block are 1 in 5.7M today (15.7K yr expected).",
        forKey: "preview_device_summary"
    )

    // Seed live metrics and a simple historical series
    let now = Date()
    var historical: [HistoricalDataPoint] = []
    for i in (0..<30) {  // 30 points at 1‑min intervals
        let t = Calendar.current.date(byAdding: .minute, value: -i, to: now) ?? now
        // Deterministic oscillation around 721.0 GH/s and 66°C
        let deltaHash = (i % 6) - 3  // -3..2
        let deltaTemp = (i % 4) - 2  // -2..1
        let point = HistoricalDataPoint(
            timestamp: t,
            hashrate: 721.0 + Double(deltaHash),
            temperature: 66 + Double(deltaTemp),
            deviceId: "192.168.1.102"
        )
        historical.append(point)
    }
    // ascending order
    historical.sort { $0.timestamp < $1.timestamp }

    let dualPoolName = "mine.ocean.xyz (65%) • publicpool.io (35%)"
    let metrics = DeviceMetrics(
        hashrate: 721.0,  // GH/s
        expectedHashrate: 721.0,
        temperature: 66,
        power: 16.1,
        uptime: TimeInterval(27 * 24 * 60 * 60),  // 27 days
        fanSpeedPercent: 82,
        timestamp: now,
        bestDifficulty: 598.7,  // in M
        inputVoltage: 0,
        asicVoltage: 0,
        measuredVoltage: 0,
        frequency: 0,
        sharesAccepted: 985,
        sharesRejected: 0,
        poolURL: dualPoolName,
        hostname: "bitaxe",
        blockHeight: 874_321,
        networkDifficulty: 83_250_000_000_000,
        asicHashrateMonitors: previewASICHashrateMonitors(),
        asicErrorPercentage: 1.42,
        vrTemperature: 54,
        isVRTemperatureKnown: true
    )

    #if DEBUG
        previewViewModel.seedPreviewData(
            deviceId: "192.168.1.102",
            metrics: metrics,
            historical: historical
        )
    #endif

    return NavigationStack {
        DeviceSummaryView(
            dashboardViewModel: previewViewModel,
            deviceName: "nerdqaxe++",
            deviceIP: "192.168.1.102",
            poolName: dualPoolName
        )
    }
}

private func makeDeviceSummaryPreviewContainer(config: ModelConfiguration) -> ModelContainer {
    do {
        return try ModelContainer(for: HistoricalDataPoint.self, configurations: config)
    } catch {
        fatalError("Failed to create device summary preview container: \(error)")
    }
}

private func previewSharedDefaults() -> UserDefaults {
    UserDefaults(suiteName: "group.matthewramsden.traxe") ?? .standard
}

private func previewASICHashrateMonitors() -> [ASICHashrateMonitor] {
    [
        ASICHashrateMonitor(
            index: 1,
            total: 325.6,
            domains: [0, 50.1, 100.2, 175.3]
        )
    ]
}
