import SwiftData
import SwiftUI

struct DeviceSummaryView: View {
    @StateObject var dashboardViewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showingSettings = false
    let deviceName: String
    let deviceIP: String
    let poolName: String?

    @State private var deviceAISummary: AISummary?
    @State private var isGeneratingDeviceSummary = false

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
                    // Device info header
                    HStack {
                        HStack(spacing: 6) {
                            //                        Text(deviceIP)
                            //                            .foregroundStyle(.primary)
                            Text(deviceName)
                                .foregroundStyle(.secondary)
                            if let poolName = poolName, !poolName.isEmpty {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text(poolName)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        Spacer()
                    }
                    .padding()

                    // Device AI Summary Section with animation
                    if AIFeatureFlags.isAvailable,
                        AIFeatureFlags.isEnabledByUser
                    {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Summary")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            // Calculate fixed height for 3 lines of body text to prevent layout shifts
                            let lineCount = 3
                            let lineHeight = UIFont.preferredFont(forTextStyle: .body).lineHeight
                            let fixedHeight = lineHeight * CGFloat(lineCount)

                            ZStack(alignment: .topLeading) {
                                if let summary = deviceAISummary {
                                    if #available(iOS 18.0, *) {
                                        AnimatedAISummaryText(
                                            content: summary.content,
                                            isDataLoaded: dashboardViewModel.connectionState
                                                == .connected
                                        )
                                        .lineLimit(lineCount)
                                        .truncationMode(.tail)
                                        .transition(.opacity)
                                    } else {
                                        FallbackAISummaryText(content: summary.content)
                                            .lineLimit(lineCount)
                                            .truncationMode(.tail)
                                            .transition(.opacity)
                                    }
                                } else {
                                    // Lightweight placeholder while generating
                                    TypingDots()
                                        .transition(.opacity)
                                }
                            }
                            .frame(height: fixedHeight)
                        }
                        .padding(.horizontal)
                        .onAppear {
                            if deviceAISummary == nil {
                                // Delay AI summary generation to prioritize data loading
                                Task {
                                    try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms delay
                                    if ProcessInfo.isPreview {
                                        // In previews, use a seed if provided
                                        let seeded = UserDefaults.standard.string(forKey: "preview_device_summary")
                                        let content = seeded ?? "Hashrate steady around 2.5 TH/s; temps mid‑60s °C; power ~620W."
                                        self.deviceAISummary = AISummary(content: content)
                                    } else {
                                        generateDeviceAISummary()
                                    }
                                }
                            }
                        }
                    }

                    if dashboardViewModel.connectionState == .connected
                        && !dashboardViewModel.historicalData.isEmpty
                    {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Hash Rate")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            //                    VStack(alignment: .center, spacing: 8) {
                            //                        SparklineView(
                            //                            data: dashboardViewModel.historicalData,
                            //                            valueKey: \.hashrate,
                            //                            style: .bars
                            //                        )
                            //                        .frame(height: 60)
                            //                    }

                            HStack(alignment: .center, spacing: 8) {
                                Spacer()
                                SparklineView(
                                    data: dashboardViewModel.historicalData,
                                    valueKey: \.hashrate,
                                    style: .bars
                                )
                                .frame(height: 60)
                                Spacer()
                            }

                        }
                        .padding(.horizontal)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Stats")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .padding(.horizontal)

                        MetricsSummaryGrid(viewModel: dashboardViewModel)
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: deviceAISummary != nil)
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
                    //                        .foregroundColor(.traxeGold)
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
        // Keep the dashboard connected while the settings sheet is presented
        .task {
            guard !ProcessInfo.isPreview else { return }
            await dashboardViewModel.connect()
            dashboardViewModel.loadHistoricalData()
        }
    }

    private func generateDeviceAISummary() {
        guard #available(iOS 18.0, macOS 15.0, *) else { return }

        // Get the current device IP from UserDefaults
        guard let sharedDefaults = UserDefaults(suiteName: "group.matthewramsden.traxe"),
            let deviceIP = sharedDefaults.string(forKey: "bitaxeIPAddress"),
            !deviceIP.isEmpty
        else {
            // No device IP available for AI summary
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
                        self.deviceAISummary = summary
                        self.isGeneratingDeviceSummary = false
                    }
                }
            } catch {
                // Failed to generate device AI summary
                await MainActor.run {
                    self.isGeneratingDeviceSummary = false
                }
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: HistoricalDataPoint.self, configurations: config)
    let previewViewModel = DashboardViewModel(modelContext: container.mainContext)

    // Seed current device selection and AI enablement
    let groupDefaults = UserDefaults(suiteName: "group.matthewramsden.traxe")!
    groupDefaults.set("192.168.1.102", forKey: "bitaxeIPAddress")
    UserDefaults.standard.set(true, forKey: "ai_enabled")
    UserDefaults.standard.set(
        "Over the last 24 hours the miner has averaged 721.0 GH/s",
        forKey: "preview_device_summary"
    )

    // Seed live metrics and a simple historical series
    let now = Date()
    var historical: [HistoricalDataPoint] = []
    for i in (0..<30) { // 30 points at 1‑min intervals
        let t = Calendar.current.date(byAdding: .minute, value: -i, to: now) ?? now
        // Deterministic oscillation around 721.0 GH/s and 66°C
        let deltaHash = (i % 6) - 3 // -3..2
        let deltaTemp = (i % 4) - 2 // -2..1
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
        hashrate: 721.0, // GH/s
        expectedHashrate: 721.0,
        temperature: 66,
        power: 16.1,
        uptime: TimeInterval(27 * 24 * 60 * 60), // 27 days
        fanSpeedPercent: 82,
        timestamp: now,
        bestDifficulty: 598.7, // in M
        inputVoltage: 0,
        asicVoltage: 0,
        measuredVoltage: 0,
        frequency: 0,
        sharesAccepted: 985,
        sharesRejected: 0,
        poolURL: "mine.ocean.xyz",
        hostname: "bitaxe"
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
