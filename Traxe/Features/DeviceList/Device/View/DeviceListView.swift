import RevenueCat
import SwiftData
import SwiftUI
import TipKit
import WidgetKit

struct WhatsNewTip: Tip {
    enum ActionID: String {
        case openWhatsNew
    }

    var id: String {
        "whatsnew-\(WhatsNewConfig.currentWhatsNewKey())"
    }

    var options: [TipOption] {
        [Tip.MaxDisplayCount(1)]
    }

    var title: Text {
        Text("See What’s New")
    }

    var message: Text? {
        Text("Version \(WhatsNewConfig.currentVersion()) updates for Traxe.")  // Text("Catch up on the latest Traxe updates.")
    }

    var image: Image? {
        Image(systemName: "sparkles")
            .symbolRenderingMode(.hierarchical)
    }

    var actions: [Action] {
        [
            Tip.Action(
                id: ActionID.openWhatsNew.rawValue,
                title: "View Updates"
            )
        ]
    }
}

struct DeviceListView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: DeviceListViewModel
    private let dashboardViewModel: DashboardViewModel
    @Binding var navigateToDeviceList: Bool

    init(
        dashboardViewModel: DashboardViewModel,
        navigateToDeviceList: Binding<Bool>,
        mockUserDefaults: UserDefaults? = nil
    ) {
        self.dashboardViewModel = dashboardViewModel
        self._navigateToDeviceList = navigateToDeviceList
        if let mockDefaults = mockUserDefaults {
            self._viewModel = State(initialValue: DeviceListViewModel(defaults: mockDefaults))
        } else {
            self._viewModel = State(initialValue: DeviceListViewModel())
        }
    }
    @State private var navigateToSummary = false
    @State private var showingFleetWeeklyRecap = false
    @State private var selectedDevice: SavedDevice? = nil
    @State private var showingWhatsNew = false
    @State private var showConnectionErrorAlert = false
    @State private var connectionErrorMessage = ""
    @State private var connectionErrorDeviceInfo = ""
    @State private var showingAddSheet = false
    @State private var showingPaywallSheet = false
    @State private var showingSubscriptionExpiredAlert = false
    @State private var customerInfo: CustomerInfo? = nil
    private var whatsNewTip = WhatsNewTip()

    private var subscriptionAccessPolicy: SubscriptionAccessPolicy {
        let proIsActive = customerInfo?.entitlements["Pro"]?.isActive == true
        let miners5IsActive = customerInfo?.entitlements["Miners_5"]?.isActive == true

        return SubscriptionAccessPolicy(
            proIsActive: proIsActive,
            miners5IsActive: miners5IsActive,
            hasLoadedSubscription: customerInfo != nil
        )
    }

    private func handleDeviceTap(device: SavedDevice, isAccessible: Bool) {
        if isAccessible {
            selectedDevice = device
            Task {
                await connectAndNavigate(to: device)
            }
        } else {
            if subscriptionAccessPolicy.shouldShowSubscriptionExpiredAlert {
                showingSubscriptionExpiredAlert = true
            }
        }
    }

    private var whatsNewTipSection: some View {
        Group {
            if viewModel.shouldShowWhatsNewTip {
                TipView(whatsNewTip, arrowEdge: .bottom) { action in
                    if action.id == WhatsNewTip.ActionID.openWhatsNew.rawValue {
                        viewModel.markWhatsNewTipSeen()
                        showingWhatsNew = true
                    }
                }
                .accentColor(.traxeGold)
                .tipBackground(Color(.secondarySystemBackground))
                .tipViewStyle(.miniTip)
                .scaleEffect(0.9)
                .padding(.top, 6)
                .padding(.horizontal)
            }
        }
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

            VStack(spacing: 0) {
                ScrollView {
                    DeviceGridSectionView(
                        viewModel: viewModel,
                        subscriptionAccessPolicy: subscriptionAccessPolicy,
                        showFleetWeeklyRecap: {
                            showingFleetWeeklyRecap = true
                        },
                        handleSelection: handleDeviceTap(device:isAccessible:)
                    )
                }
                .refreshable {
                    await viewModel.updateAggregatedStats()
                }
                .allowsHitTesting(!viewModel.isEditMode)
            }
            .safeAreaInset(edge: .top) {
                whatsNewTipSection
            }

            if viewModel.isEditMode {
                DeviceEditModeOverlayView(
                    viewModel: viewModel,
                    subscriptionAccessPolicy: subscriptionAccessPolicy
                )
            }
        }
        .navigationTitle("Traxe")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !viewModel.savedDevices.isEmpty {
                    Button(viewModel.isEditMode ? "Done" : "Edit") {
                        withAnimation {
                            viewModel.isEditMode.toggle()
                        }
                    }
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    let deviceLimit: Int
                    if customerInfo == nil {
                        // Preserve previous UX for add flow while subscription is loading.
                        deviceLimit = 1
                    } else {
                        deviceLimit = subscriptionAccessPolicy.deviceLimit
                    }

                    if viewModel.savedDevices.count < deviceLimit {
                        showingAddSheet = true
                    } else {
                        // User is at or over their limit (or has 0 devices but somehow no free slot logic triggered, though current logic covers this), show paywall
                        showingPaywallSheet = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.traxeGold)
                }
            }
        }
        .onAppear {
            let didConfigureModelContext = viewModel.configureModelContextIfNeeded(modelContext)
            if didConfigureModelContext {
                Task {
                    await viewModel.updateAggregatedStats()
                }
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                Task {
                    await viewModel.updateAggregatedStats()
                }
            }
        }
        .onChange(of: navigateToSummary) { wasNavigating, isNavigating in
            if wasNavigating && !isNavigating {
                Task {
                    await viewModel.updateAggregatedStats()
                }
            }
        }
        .onChange(of: viewModel.savedDevices.isEmpty) { _, isEmptyNow in
            if isEmptyNow {
                self.navigateToDeviceList = false
                dismiss()
            }
        }
        .task {
            for await info in Purchases.shared.customerInfoStream {
                self.customerInfo = info
            }
        }
        .sheet(
            isPresented: $showingAddSheet,
            onDismiss: {
                viewModel.loadDevices()
            }
        ) {
            AddDeviceView()
        }
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewSheetView(
                content: WhatsNewConfig.content,
                accentColor: .traxeGold,
                requestReview: {
                    viewModel.requestReview()
                },
                sendSupportEmail: {
                    viewModel.sendSupportEmail()
                },
                openSourceRepo: {
                    viewModel.openSourceRepo()
                }
            )
        }
        .sheet(isPresented: $showingPaywallSheet) {
            PaywallView()
        }
        .navigationDestination(isPresented: $navigateToSummary) {
            if let device = selectedDevice {
                DeviceSummaryView(
                    dashboardViewModel: dashboardViewModel,
                    deviceName: viewModel.deviceMetrics[device.ipAddress]?.hostname ?? device.name,
                    deviceIP: device.ipAddress,
                    poolName: viewModel.deviceMetrics[device.ipAddress]?.poolURL
                )
            } else {
                Text("Error: No miner selected")
            }
        }
        .navigationDestination(isPresented: $showingFleetWeeklyRecap) {
            WeeklyRecapView(
                scope: .fleet(
                    devices: viewModel.savedDevices.map { device in
                        WeeklyRecapFleetDevice(
                            id: device.ipAddress,
                            name: viewModel.deviceMetrics[device.ipAddress]?.hostname
                                ?? device.name,
                            poolName: viewModel.deviceMetrics[device.ipAddress]?.poolURL,
                            currentHashrate: viewModel.deviceMetrics[device.ipAddress]?.hashrate
                                ?? 0
                        )
                    }
                )
            )
        }
        .alert("Connection Failed", isPresented: $showConnectionErrorAlert) {
            Button("OK") {}
        } message: {
            var message = connectionErrorMessage
            if !connectionErrorDeviceInfo.isEmpty {
                message += "\n\n\(connectionErrorDeviceInfo)"
            }
            return Text(message)
        }
        .alert("Monthly Subscription Expired", isPresented: $showingSubscriptionExpiredAlert) {
            Button("OK") {}
        } message: {
            Text("Your monthly subscription has expired. Please renew to access this miner.")
        }
        .task {
            for await status in whatsNewTip.statusUpdates {
                await MainActor.run {
                    viewModel.handleWhatsNewTipStatus(status)
                }
            }
        }
    }

    private func connectAndNavigate(to device: SavedDevice) async {
        showConnectionErrorAlert = false
        connectionErrorMessage = ""
        connectionErrorDeviceInfo = ""

        if let sharedDefaults = UserDefaults(suiteName: "group.matthewramsden.traxe") {
            sharedDefaults.set(device.ipAddress, forKey: "bitaxeIPAddress")
            WidgetCenter.shared.reloadTimelines(ofKind: "TraxeWidget")
        } else {
            connectionErrorMessage = "Internal error: Could not save selected IP address."
            showConnectionErrorAlert = true
            return
        }

        await dashboardViewModel.connect()

        if dashboardViewModel.connectionState == .connected {
            // Preload a larger historical window so device summary has trend context immediately
            dashboardViewModel.preloadHistoricalData()
            navigateToSummary = true
        } else {
            // Always use the dashboard error message if available, even if empty
            connectionErrorMessage =
                dashboardViewModel.errorMessage.isEmpty
                ? "Could not connect to the miner at \(device.ipAddress). Please check the IP and network."
                : dashboardViewModel.errorMessage

            connectionErrorDeviceInfo = dashboardViewModel.errorDeviceInfo
            showConnectionErrorAlert = true
            navigateToSummary = false
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = makeDeviceListPreviewContainer(config: config)
    let previewDashboardVM = DashboardViewModel(modelContext: container.mainContext)

    // Use the app group defaults so the view model and cache read the same store
    let groupDefaults = previewGroupDefaults()

    // Seed devices
    let devices = [
        SavedDevice(name: "nerdqaxe++", ipAddress: "192.168.1.101"),
        SavedDevice(name: "bitaxe", ipAddress: "192.168.1.102"),
        SavedDevice(name: "octaxe", ipAddress: "192.168.1.103"),
        SavedDevice(name: "lucky", ipAddress: "192.168.1.104"),
    ]
    let devEncoder = JSONEncoder()
    if let encodedDevices = try? devEncoder.encode(devices) {
        groupDefaults.set(encodedDevices, forKey: "savedDevices")
    }

    // Enable AI features for previews
    UserDefaults.standard.set(true, forKey: "ai_enabled")

    // Seed cached device metrics so cards and totals are populated (hashrate in GH/s)
    let cached: [String: CachedDeviceMetrics] = [
        "192.168.1.101": CachedDeviceMetrics(
            from: DeviceMetrics(hashrate: 5100, temperature: 61, power: 600, hostname: "nerdqaxe++")
        ),
        "192.168.1.102": CachedDeviceMetrics(
            from: DeviceMetrics(hashrate: 721, temperature: 65, power: 620, hostname: "bitaxe")
        ),
        "192.168.1.103": CachedDeviceMetrics(
            from: DeviceMetrics(hashrate: 450, temperature: 68, power: 610, hostname: "octaxe")
        ),
        "192.168.1.104": CachedDeviceMetrics(
            from: DeviceMetrics(hashrate: 3800, temperature: 72, power: 620, hostname: "lucky")
        ),
    ]
    let cacheEncoder = JSONEncoder()
    cacheEncoder.dateEncodingStrategy = .iso8601
    if let encodedCache = try? cacheEncoder.encode(cached) {
        groupDefaults.set(encodedCache, forKey: "cachedDeviceMetricsV2")
    }

    // Seed a cached fleet AI summary so the preview doesn't need networking
    struct _FleetSummaryCacheEntry: Codable {
        let content: String
        let generatedAt: Date
        let deviceCount: Int
    }
    let summaryContent =
        "\(devices.count) miners producing a total of 10.1 TH/s, with a temperature range of 61-72°C, and consuming 2450W of power."
    let summaryEncoder = JSONEncoder()
    summaryEncoder.dateEncodingStrategy = .iso8601
    if let encodedSummary = try? summaryEncoder.encode(
        _FleetSummaryCacheEntry(
            content: summaryContent,
            generatedAt: Date(),
            deviceCount: devices.count
        )
    ) {
        groupDefaults.set(encodedSummary, forKey: "cachedFleetAISummaryV1")
    }

    return NavigationStack {
        // Important: do not pass mockUserDefaults; use app group store
        DeviceListView(
            dashboardViewModel: previewDashboardVM,
            navigateToDeviceList: .constant(true)
        )
    }
    .modelContainer(container)
}

#Preview("Whats New Tip Visible") {
    let _ = {
        WhatsNewConfig.isEnabledForCurrentBuild = true
        WhatsNewConfig.currentAnnouncementID = UUID().uuidString
        try? Tips.resetDatastore()
        try? Tips.configure([
            .datastoreLocation(.applicationDefault),
            .displayFrequency(.immediate),
        ])
    }()

    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = makeDeviceListPreviewContainer(config: config)
    let previewDashboardVM = DashboardViewModel(modelContext: container.mainContext)

    let groupDefaults = previewGroupDefaults()
    groupDefaults.set("preview-previous-announcement", forKey: "lastSeenWhatsNewVersion")

    return NavigationStack {
        DeviceListView(
            dashboardViewModel: previewDashboardVM,
            navigateToDeviceList: .constant(true),
            mockUserDefaults: groupDefaults
        )
    }
    .modelContainer(container)
}

private func makeDeviceListPreviewContainer(config: ModelConfiguration) -> ModelContainer {
    do {
        return try ModelContainer(for: HistoricalDataPoint.self, configurations: config)
    } catch {
        fatalError("Failed to create device list preview container: \(error)")
    }
}

private func previewGroupDefaults() -> UserDefaults {
    UserDefaults(suiteName: "group.matthewramsden.traxe") ?? .standard
}
