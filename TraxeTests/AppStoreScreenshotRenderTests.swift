import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import Traxe

private let screenshotPointSize = CGSize(width: 440, height: 956)
private let screenshotScale: CGFloat = 3

@MainActor
final class AppStoreScreenshotRenderTests: XCTestCase {
    private var outputDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        setenv("XCODE_RUNNING_FOR_PREVIEWS", "1", 1)
        UIView.setAnimationsEnabled(false)

        UserDefaults.standard.set(true, forKey: "ai_enabled")
        UserDefaults.standard.set(
            "Miner is steady; temps are holding and power stays consistent.",
            forKey: "preview_device_summary"
        )

        outputDirectory = try Self.makeOutputDirectory()
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        try Self.removeExistingPNGs(in: outputDirectory)
    }

    override func tearDownWithError() throws {
        UIView.setAnimationsEnabled(true)
        try super.tearDownWithError()
    }

    func testRenderAppStoreScreenshots() async throws {
        try await render(
            fileName: "01_fleet-dashboard.png",
            colorScheme: .dark,
            settleDuration: .milliseconds(800)
        ) {
            FleetDashboardScreenshotView()
        }

        UserDefaults.standard.set(
            "Hashrate rebounded to 720 GH/s; temps sit near 64 C and power is steady.",
            forKey: "preview_device_summary"
        )
        try await render(
            fileName: "02_device-summary.png",
            colorScheme: .dark,
            settleDuration: .seconds(6)
        ) {
            DeviceSummaryScreenshotView(
                deviceID: PreviewFixtures.sampleSecondaryDeviceID,
                deviceName: "bitaxe",
                metrics: makeSummaryMetrics(
                    deviceID: PreviewFixtures.sampleSecondaryDeviceID,
                    profile: .bitaxeRecovery
                ),
                historicalData: makeSummaryHistoricalData(
                    deviceID: PreviewFixtures.sampleSecondaryDeviceID,
                    profile: .bitaxeRecovery
                )
            )
        }

        UserDefaults.standard.set(
            "Hashrate drifted between 680 and 735 GH/s; temps nudged up to 66 C while power stayed low.",
            forKey: "preview_device_summary"
        )
        try await render(
            fileName: "03_device-summary-light.png",
            colorScheme: .light,
            settleDuration: .seconds(6)
        ) {
            DeviceSummaryScreenshotView(
                deviceID: PreviewFixtures.sampleSecondaryDeviceID,
                deviceName: "bitaxe",
                metrics: makeSummaryMetrics(
                    deviceID: PreviewFixtures.sampleSecondaryDeviceID,
                    profile: .bitaxeDip
                ),
                historicalData: makeSummaryHistoricalData(
                    deviceID: PreviewFixtures.sampleSecondaryDeviceID,
                    profile: .bitaxeDip
                )
            )
        }

        UserDefaults.standard.set(
            "Dual-pool hashrate is climbing toward 5.2 TH/s; temps hover near 63 C with steady power.",
            forKey: "preview_device_summary"
        )
        try await render(
            fileName: "04_device-summary-dual-pool.png",
            colorScheme: .dark,
            settleDuration: .seconds(6)
        ) {
            DeviceSummaryScreenshotView(
                deviceID: PreviewFixtures.sampleDeviceID,
                deviceName: "nerdqaxe++",
                metrics: makeSummaryMetrics(
                    deviceID: PreviewFixtures.sampleDeviceID,
                    poolName: PreviewFixtures.sampleDualPoolName,
                    profile: .nerdqaxeDualPool
                ),
                historicalData: makeSummaryHistoricalData(
                    deviceID: PreviewFixtures.sampleDeviceID,
                    profile: .nerdqaxeDualPool
                ),
                poolName: PreviewFixtures.sampleDualPoolName
            )
        }

        try await render(
            fileName: "05_advanced-settings.png",
            colorScheme: .dark,
            settleDuration: .milliseconds(800)
        ) {
            AdvancedSettingsScreenshotView()
        }

        try await render(
            fileName: "06_weekly-recap-device.png",
            colorScheme: .dark,
            settleDuration: .seconds(1)
        ) {
            WeeklyRecapDeviceScreenshotView()
        }

        try await render(
            fileName: "07_weekly-recap-fleet.png",
            colorScheme: .dark,
            settleDuration: .seconds(1)
        ) {
            WeeklyRecapFleetScreenshotView()
        }
    }

    private func render<Content: View>(
        fileName: String,
        colorScheme: ColorScheme,
        settleDuration: Duration,
        @ViewBuilder content: @escaping () -> Content
    ) async throws {
        let rootView = ScreenshotCanvas(colorScheme: colorScheme, content: content)
        let host = UIHostingController(rootView: rootView)
        host.overrideUserInterfaceStyle =
            colorScheme == .dark ? UIUserInterfaceStyle.dark : UIUserInterfaceStyle.light

        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first
        {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: screenshotPointSize))
        }

        window.frame = CGRect(origin: .zero, size: screenshotPointSize)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.backgroundColor = colorScheme == .dark ? UIColor.black : UIColor.white
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        try await Task.sleep(for: settleDuration)

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = screenshotScale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: screenshotPointSize, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }

        guard let data = image.pngData() else {
            XCTFail("Failed to encode \(fileName)")
            return
        }

        let outputURL = outputDirectory.appendingPathComponent(fileName)
        try data.write(to: outputURL, options: [.atomic])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        window.isHidden = true
    }

    private static func makeOutputDirectory() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let repositoryRoot = URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        if let path = environment["TRAXE_SCREENSHOT_OUTPUT_DIR"], !path.isEmpty {
            if path.hasPrefix("/") {
                return URL(fileURLWithPath: path, isDirectory: true)
            }

            return repositoryRoot.appendingPathComponent(path, isDirectory: true)
        }

        return repositoryRoot.appendingPathComponent(
            "screenshots/raw/en-US/APP_IPHONE_67",
            isDirectory: true
        )
    }

    private static func removeExistingPNGs(in directory: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }

        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for file in files where file.pathExtension == "png" {
            try FileManager.default.removeItem(at: file)
        }
    }
}

private struct ScreenshotCanvas<Content: View>: View {
    let colorScheme: ColorScheme
    let content: () -> Content

    var body: some View {
        content()
            .frame(width: screenshotPointSize.width, height: screenshotPointSize.height)
            .clipped()
            .preferredColorScheme(colorScheme)
            .environment(\.dynamicTypeSize, .medium)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0) ?? .current)
            .overlay(alignment: .top) {
                ScreenshotStatusBar(colorScheme: colorScheme)
            }
    }
}

private struct ScreenshotStatusBar: View {
    let colorScheme: ColorScheme

    private var foregroundStyle: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        HStack {
            Text("9:41")
                .font(.system(size: 15, weight: .semibold))

            Spacer()

            HStack(spacing: 7) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100percent")
            }
            .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(foregroundStyle)
        .padding(.horizontal, 28)
        .frame(height: 54)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }
}

private struct FleetDashboardScreenshotView: View {
    @State private var viewModel: DeviceListViewModel

    @MainActor
    init() {
        _viewModel = State(initialValue: makeFleetDashboardScreenshotViewModel())
    }

    var body: some View {
        NavigationStack {
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
                    DeviceGridSectionView(
                        viewModel: viewModel,
                        subscriptionAccessPolicy: PreviewFixtures.sampleSubscriptionAccessPolicy,
                        showFleetWeeklyRecap: {},
                        handleSelection: { _, _ in }
                    )
                }
            }
            .navigationTitle("Traxe")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Edit") {}
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {} label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Color.traxeGold)
                    }
                }
            }
        }
    }
}

private struct DeviceSummaryScreenshotView: View {
    private let context: DashboardPreviewContext
    private let deviceName: String
    private let deviceIP: String
    private let poolName: String?

    @MainActor
    init(
        deviceID: String,
        deviceName: String,
        metrics: DeviceMetrics,
        historicalData: [HistoricalDataPoint],
        poolName: String? = nil
    ) {
        let context = PreviewFixtures.makeDashboardPreviewContext(
            deviceId: deviceID,
            metrics: metrics
        )
        #if DEBUG
            context.viewModel.seedPreviewData(
                deviceId: deviceID,
                metrics: metrics,
                historical: historicalData
            )
        #endif
        self.context = context
        self.deviceName = deviceName
        self.deviceIP = deviceID
        self.poolName = poolName
    }

    var body: some View {
        NavigationStack {
            DeviceSummaryView(
                dashboardViewModel: context.viewModel,
                deviceName: deviceName,
                deviceIP: deviceIP,
                poolName: poolName
            )
        }
        .modelContainer(context.container)
    }
}

private struct AdvancedSettingsScreenshotView: View {
    private let context: SettingsPreviewContext

    @MainActor
    init() {
        self.context = PreviewFixtures.makeSettingsPreviewContext { viewModel in
            viewModel.isAutoFan = true
        }
    }

    var body: some View {
        NavigationStack {
            AdvancedSettingsView(viewModel: context.viewModel)
        }
        .modelContainer(context.container)
    }
}

private struct WeeklyRecapDeviceScreenshotView: View {
    private let container: ModelContainer

    @MainActor
    init() {
        self.container = makeScreenshotModelContainer()
        seedWeeklyRecapScreenshotData(in: container.mainContext)
    }

    var body: some View {
        NavigationStack {
            WeeklyRecapView(
                scope: .device(
                    deviceID: PreviewFixtures.sampleDeviceID,
                    deviceName: "nerdqaxe++",
                    poolName: PreviewFixtures.sampleDualPoolName
                ),
                initialLatestBlockHeightsByPoolSlug:
                    PreviewFixtures.sampleLatestBlockHeightsByPoolSlug
            )
        }
        .modelContainer(container)
    }
}

private struct WeeklyRecapFleetScreenshotView: View {
    private let container: ModelContainer

    @MainActor
    init() {
        self.container = makeScreenshotModelContainer()
        seedWeeklyRecapScreenshotData(in: container.mainContext)
    }

    var body: some View {
        NavigationStack {
            WeeklyRecapView(
                scope: PreviewFixtures.sampleFleetScope,
                initialLatestBlockHeightsByPoolSlug:
                    PreviewFixtures.sampleLatestBlockHeightsByPoolSlug
            )
        }
        .modelContainer(container)
    }
}

@MainActor
private func makeFleetDashboardScreenshotViewModel() -> DeviceListViewModel {
    let viewModel = PreviewFixtures.makeDeviceListViewModel()
    let offlineDevices = [
        SavedDevice(name: "shed", ipAddress: "192.168.1.104"),
        SavedDevice(name: "workbench", ipAddress: "192.168.1.105"),
    ]
    let onlineDevices = PreviewFixtures.sampleSavedDevices

    viewModel.savedDevices = onlineDevices + offlineDevices
    viewModel.deviceMetrics = PreviewFixtures.sampleDeviceMetricsByIP
    viewModel.reachableIPs = Set(onlineDevices.map(\.ipAddress))
    viewModel.totalHashRate = PreviewFixtures.sampleDeviceMetricsByIP.values.reduce(0) {
        $0 + $1.hashrate
    }
    viewModel.totalPower = PreviewFixtures.sampleDeviceMetricsByIP.values.reduce(0) {
        $0 + $1.power
    }
    viewModel.bestOverallDiff =
        PreviewFixtures.sampleDeviceMetricsByIP.values.map(\.bestDifficulty).max() ?? 0
    viewModel.fleetAISummary = AISummary(
        content:
            "5 miners configured with 3 online at 6.2 TH/s, a temp range of 61-69 C, and 644W of power."
    )
    viewModel.markAggregatedStatsRefreshCompletedForPreview()

    return viewModel
}

private enum SummaryScreenshotProfile {
    case bitaxeRecovery
    case bitaxeDip
    case nerdqaxeDualPool
}

private func makeSummaryMetrics(
    deviceID: String,
    poolName: String? = nil,
    profile: SummaryScreenshotProfile
) -> DeviceMetrics {
    var metrics = PreviewFixtures.sampleDeviceMetricsByIP[deviceID] ?? .placeholder
    metrics.poolURL = poolName ?? metrics.poolURL

    switch profile {
    case .bitaxeRecovery:
        metrics.hashrate = 720
        metrics.expectedHashrate = 735
        metrics.temperature = 64
        metrics.power = 18
        metrics.uptime = 18 * 60 * 60
        metrics.sharesAccepted = 985
        metrics.asicHashrateMonitors = [
            ASICHashrateMonitor(index: 1, total: 720, domains: [164, 178, 192, 186])
        ]
        metrics.asicErrorPercentage = 0.4
        metrics.vrTemperature = 52

    case .bitaxeDip:
        metrics.hashrate = 705
        metrics.expectedHashrate = 735
        metrics.temperature = 66
        metrics.power = 19
        metrics.uptime = 21 * 60 * 60
        metrics.sharesAccepted = 1_018
        metrics.asicHashrateMonitors = [
            ASICHashrateMonitor(index: 1, total: 705, domains: [176, 169, 182, 178])
        ]
        metrics.asicErrorPercentage = 0.7
        metrics.vrTemperature = 54

    case .nerdqaxeDualPool:
        metrics.hashrate = 5_160
        metrics.expectedHashrate = 5_250
        metrics.temperature = 63
        metrics.power = 612
        metrics.uptime = 39 * 60 * 60
        metrics.sharesAccepted = 1_310
        metrics.asicHashrateMonitors = [
            ASICHashrateMonitor(index: 1, total: 1_322, domains: [324, 338, 317, 343]),
            ASICHashrateMonitor(index: 2, total: 1_291, domains: [315, 329, 331, 316]),
            ASICHashrateMonitor(index: 3, total: 1_268, domains: [306, 318, 322, 322]),
            ASICHashrateMonitor(index: 4, total: 1_279, domains: [319, 309, 327, 324]),
        ]
        metrics.asicErrorPercentage = 0.5
        metrics.vrTemperature = 53
    }

    metrics.isVRTemperatureKnown = true
    return metrics
}

private func makeSummaryHistoricalData(
    deviceID: String,
    profile: SummaryScreenshotProfile
) -> [HistoricalDataPoint] {
    let values: [Double]
    let baseTemperature: Double

    switch profile {
    case .bitaxeRecovery:
        values = [
            612, 628, 650, 684, 705, 731, 716, 724, 736, 721, 729, 720,
            733, 726, 739, 725, 734, 720,
        ]
        baseTemperature = 64

    case .bitaxeDip:
        values = [
            736, 724, 708, 688, 672, 681, 699, 716, 704, 691, 710, 725,
            717, 706, 731, 712, 720, 705,
        ]
        baseTemperature = 66

    case .nerdqaxeDualPool:
        values = [
            4_780, 4_910, 5_030, 4_960, 5_110, 5_220, 5_080, 5_260, 5_150,
            5_310, 5_210, 5_360, 5_240, 5_330, 5_180, 5_390, 5_280, 5_160,
        ]
        baseTemperature = 63
    }

    let now = Date()
    let calendar = Calendar.current
    return values.enumerated().map { offset, value in
        let timestamp =
            calendar.date(byAdding: .minute, value: (offset - values.count + 1) * 8, to: now)
            ?? now
        let temperature = baseTemperature + Double((offset % 5) - 2)
        return HistoricalDataPoint(
            timestamp: timestamp,
            hashrate: value,
            temperature: temperature,
            deviceId: deviceID
        )
    }
}

private func makeScreenshotModelContainer() -> ModelContainer {
    do {
        return try ModelContainer(
            for: HistoricalDataPoint.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    } catch {
        fatalError("Failed to create screenshot model container: \(error)")
    }
}

@MainActor
private func seedWeeklyRecapScreenshotData(in modelContext: ModelContext) {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let devices: [(id: String, baseHashrate: Double, baseTemperature: Double)] = [
        (PreviewFixtures.sampleDeviceID, 5_100, 61),
        (PreviewFixtures.sampleSecondaryDeviceID, 720, 64),
    ]

    for dayOffset in 0..<7 {
        guard let day = calendar.date(byAdding: .day, value: dayOffset - 6, to: today) else {
            continue
        }

        for device in devices {
            for sampleIndex in 0..<4 {
                let timestamp =
                    calendar.date(
                        byAdding: .hour,
                        value: 6 + (sampleIndex * 4),
                        to: day
                    ) ?? day
                let hashrateDrift = Double((dayOffset + sampleIndex) % 5 - 2)
                let temperatureDrift = Double((dayOffset + sampleIndex) % 4 - 1)
                modelContext.insert(
                    HistoricalDataPoint(
                        timestamp: timestamp,
                        hashrate: device.baseHashrate + (hashrateDrift * device.baseHashrate * 0.02),
                        temperature: device.baseTemperature + temperatureDrift,
                        deviceId: device.id
                    )
                )
            }
        }
    }

    try? modelContext.save()
}
