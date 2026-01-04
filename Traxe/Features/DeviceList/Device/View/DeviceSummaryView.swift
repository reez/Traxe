import Foundation
import SimpleToast
import SwiftData
import SwiftUI
import UIKit

struct DeviceSummaryView: View {
    @StateObject var dashboardViewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showingSettings = false
    @State private var showBlockFoundToast = false
    @State private var lastBlockFoundValue: Int? = nil
    let deviceName: String
    let deviceIP: String
    let poolName: String?

    @State private var deviceAISummary: AISummary?
    @State private var isGeneratingDeviceSummary = false
    private var displayPoolName: String? { dashboardViewModel.currentMetrics.poolURL ?? poolName }
    private var poolSegments: [PoolDisplaySegment] {
        guard let poolName = displayPoolName else { return [] }
        return poolSegments(from: poolName)
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
                    // Device info header
                    HStack {
                        HStack(spacing: 6) {
                            //                        Text(deviceIP)
                            //                            .foregroundStyle(.primary)
                            Text(deviceName)
                                .foregroundStyle(.secondary)
                            if !poolSegments.isEmpty {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 6) {
                                    ForEach(Array(poolSegments.enumerated()), id: \.offset) {
                                        index,
                                        segment in
                                        if index > 0 {
                                            Text("•")
                                                .foregroundStyle(.secondary)
                                        }
                                        HStack(spacing: 6) {
                                            poolIcon(for: segment.logoName)
                                            Text(segment.text)
                                        }
                                    }
                                }
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
                                        let seeded = UserDefaults.standard.string(
                                            forKey: "preview_device_summary"
                                        )
                                        let content =
                                            seeded
                                            ?? "Hashrate steady around 2.5 TH/s; temps mid‑60s °C; power ~620W."
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
        .onAppear {
            lastBlockFoundValue = dashboardViewModel.currentMetrics.blockFound
        }
        .onChange(of: dashboardViewModel.currentMetrics.blockFound) { _, newValue in
            let previousValue = lastBlockFoundValue
            lastBlockFoundValue = newValue

            guard dashboardViewModel.connectionState == .connected else { return }
            guard newValue == 1, previousValue != 1 else { return }
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

    private struct PoolDisplaySegment: Identifiable {
        let id = UUID()
        let text: String
        let logoName: String?
    }

    private func poolSegments(from poolDisplayName: String) -> [PoolDisplaySegment] {
        let segments =
            poolDisplayName
            .components(separatedBy: "\u{2022}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return segments.map { segment in
            let host = normalizedHost(from: segment)
            return PoolDisplaySegment(
                text: segment,
                logoName: host.flatMap(poolLogoName(for:))
            )
        }
    }

    @ViewBuilder
    private func poolIcon(for logoName: String?) -> some View {
        let iconSize = UIFont.preferredFont(forTextStyle: .caption2).pointSize
        if let logoName, let image = UIImage(named: logoName) {
            Image(uiImage: image)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
        } else {
            Image(systemName: "hammer.fill")
                .font(.caption2)
        }
    }

    private func poolLogoName(for host: String) -> String? {
        if host.contains("ocean") {
            return "ocean"
        }
        if host.contains("public-pool") || host.contains("publicpool") {
            return "publicpool"
        }
        if host.contains("parasite") {
            return "parasite"
        }
        return nil
    }

    private func normalizedHost(from raw: String) -> String? {
        let base = raw.split(separator: "(").first.map(String.init) ?? ""
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let host = url.host {
            return host.lowercased()
        }

        if let url = URL(string: "stratum://\(trimmed)"), let host = url.host {
            return host.lowercased()
        }

        let hostPort = trimmed.split(separator: "/").first ?? ""
        let host = hostPort.split(separator: ":").first ?? ""
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
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

private struct BlockFoundToastView: View {
    let blockHeight: Int?
    let poolName: String?

    private var formattedBlockHeight: String? {
        guard let blockHeight else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: blockHeight)) ?? "\(blockHeight)"
    }

    private var messageText: String {
        let poolSuffix = (poolName?.isEmpty == false) ? " by \(poolName ?? "")" : ""
        if let formattedHeight = formattedBlockHeight {
            return "Block \(formattedHeight) found\(poolSuffix)"
        }
        return "Block found\(poolSuffix)"
    }

    var body: some View {
        HStack {
            Text(messageText)
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.secondary.opacity(0.3), lineWidth: 0.5)
        )
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
