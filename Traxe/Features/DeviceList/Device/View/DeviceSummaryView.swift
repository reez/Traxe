import Foundation
import SimpleToast
import SwiftData
import SwiftUI

struct DeviceSummaryView: View {
    let dashboardViewModel: DashboardViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var showingSettings = false
    @State private var showingWeeklyRecap = false
    @State private var showBlockFoundToast = false
    @State private var lastBlockFoundValue: Int? = nil
    let deviceName: String
    let deviceIP: String
    let poolName: String?

    @State private var deviceAISummary: AISummary?
    @State private var isGeneratingDeviceSummary = false

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

                    if AIFeatureFlags.isAvailable,
                        AIFeatureFlags.isEnabledByUser
                    {
                        DeviceAISummarySectionView(
                            summary: deviceAISummary,
                            isDataLoaded: dashboardViewModel.connectionState == .connected
                        )
                        .padding(.horizontal)
                        .onAppear {
                            if deviceAISummary == nil {
                                Task {
                                    try? await Task.sleep(for: .milliseconds(500))
                                    if ProcessInfo.isPreview {
                                        let seeded = UserDefaults.standard.string(
                                            forKey: "preview_device_summary"
                                        )
                                        let content =
                                            seeded
                                            ?? "Hashrate steady around 2.5 TH/s; temps mid‑60s °C; power ~620W."
                                        deviceAISummary = AISummary(content: content)
                                    } else {
                                        generateDeviceAISummary()
                                    }
                                }
                            }
                        }
                    }

                    if dashboardViewModel.connectionState == .connected,
                        !dashboardViewModel.historicalData.isEmpty
                    {
                        DeviceSummaryHashrateSectionView(
                            historicalData: dashboardViewModel.historicalData
                        )
                        .padding(.horizontal)
                    }

                    WeeklyRecapNavigationTile(viewData: .device) {
                        showingWeeklyRecap = true
                    }
                    .padding(.horizontal)

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
                .animation(.easeInOut(duration: 0.4), value: deviceAISummary != nil)
            }
            .debugBlockFoundToast {
                showBlockFoundToast = true
            }
        }
        .navigationTitle(deviceIP)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            let sharedDefaults = UserDefaults(
                suiteName: SettingsViewModel.sharedUserDefaultsSuiteName
            )
            let settingsViewModel = SettingsViewModel(
                sharedUserDefaults: sharedDefaults,
                modelContext: modelContext
            )
            SettingsView(viewModel: settingsViewModel)
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
        .task {
            guard !ProcessInfo.isPreview else { return }
            await dashboardViewModel.connect()
            dashboardViewModel.loadHistoricalData()
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

    private func generateDeviceAISummary() {
        guard #available(iOS 18.0, macOS 15.0, *) else { return }

        guard let sharedDefaults = UserDefaults(suiteName: "group.matthewramsden.traxe"),
            let deviceIP = sharedDefaults.string(forKey: "bitaxeIPAddress"),
            !deviceIP.isEmpty
        else {
            return
        }

        isGeneratingDeviceSummary = true

        Task {
            do {
                let aiService = AIAnalysisService()
                let summary = try await aiService.generateDeviceSummary(
                    forDevice: deviceIP,
                    withHistoricalData: dashboardViewModel.historicalData
                )

                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        deviceAISummary = summary
                        isGeneratingDeviceSummary = false
                    }
                }
            } catch {
                await MainActor.run {
                    isGeneratingDeviceSummary = false
                }
            }
        }
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
        "Over the last 24 hours the miner has averaged 721.0 GH/s",
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
        networkDifficulty: 83_250_000_000_000
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
        "Over the last 24 hours the miner has averaged 721.0 GH/s",
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
        networkDifficulty: 83_250_000_000_000
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
