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
    @State private var navigation: DeviceListNavigationState
    private let dashboardViewModel: DashboardViewModel
    @Binding var navigateToDeviceList: Bool

    init(
        dashboardViewModel: DashboardViewModel,
        navigateToDeviceList: Binding<Bool>,
        mockUserDefaults: UserDefaults? = nil,
        viewModelDependencies: DeviceListViewModel.Dependencies = .live,
        initialNavigationState: DeviceListNavigationState = DeviceListNavigationState()
    ) {
        self.dashboardViewModel = dashboardViewModel
        self._navigateToDeviceList = navigateToDeviceList
        self._navigation = State(initialValue: initialNavigationState)
        if let mockDefaults = mockUserDefaults {
            self._viewModel = State(
                initialValue: DeviceListViewModel(
                    defaults: mockDefaults,
                    dependencies: viewModelDependencies
                )
            )
        } else {
            self._viewModel = State(
                initialValue: DeviceListViewModel(dependencies: viewModelDependencies)
            )
        }
    }

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

    private var addDeviceLimit: Int {
        if customerInfo == nil {
            // Preserve previous UX for add flow while subscription is loading.
            return 1
        }

        return subscriptionAccessPolicy.deviceLimit
    }

    private func handleDeviceTap(device: SavedDevice, isAccessible: Bool) {
        if isAccessible {
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
        // One two-column split view for every width. `NavigationSplitView` decides when
        // to collapse; the app only supplies the selection and the column a collapsed
        // layout should show, so selection and nested navigation survive resizing.
        NavigationSplitView(preferredCompactColumn: $navigation.preferredCompactColumn) {
            sidebar
        } detail: {
            NavigationStack {
                detail(for: navigation.detailFeature)
                    // Switching to a different feature starts that feature fresh instead
                    // of handing it the previous one's state. The identity only tracks
                    // the selection, so collapsing and expanding leaves it untouched.
                    .id(navigation.detailFeature)
            }
        }
        // Keep the dashboard beside the detail whenever the system has room for both.
        .navigationSplitViewStyle(.balanced)
        .onChange(of: navigation.preferredCompactColumn) { previousColumn, currentColumn in
            // Back in a collapsed layout reveals the dashboard while keeping the selected
            // feature, so the fleet totals refresh on the column transition rather than
            // when a selection is cleared.
            guard
                DeviceListNavigationState.revealsDashboard(
                    from: previousColumn,
                    to: currentColumn
                )
            else { return }

            Task {
                await viewModel.updateAggregatedStats()
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                Task {
                    await viewModel.updateAggregatedStats()
                }
            }
        }
        .onChange(of: viewModel.savedDevices.map(\.ipAddress)) { _, ipAddresses in
            // Any deletion path, including the edit-mode list, must drop a retained
            // selection for the removed miner so no column shows stale detail.
            navigation.reconcileSelection(
                withSavedMinerIPAddresses: Set(ipAddresses),
                relocatedIPAddresses: viewModel.recentRelocations
            )

            if ipAddresses.isEmpty {
                self.navigateToDeviceList = false
                dismiss()
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
        // App-wide presentations stay on the split view rather than on a column, so
        // collapsing or expanding never changes their presentation identity.
        .sheet(
            isPresented: $showingAddSheet,
            onDismiss: {
                viewModel.loadDevices()
            }
        ) {
            AddDeviceView(
                existingDeviceIPs: Set(viewModel.savedDevices.map(\.ipAddress)),
                deviceLimit: addDeviceLimit
            )
        }
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewSheetView(
                content: WhatsNewConfig.content,
                accentColor: .traxeGold,
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
        .alert("Connection Failed", isPresented: $showConnectionErrorAlert) {
            Button("OK") {}
        } message: {
            var message = connectionErrorMessage
            if !connectionErrorDeviceInfo.isEmpty {
                message += "\n\n\(connectionErrorDeviceInfo)"
            }
            return Text(message)
        }
        .alert("Plan Limit Reached", isPresented: $showingSubscriptionExpiredAlert) {
            Button("OK") {}
        } message: {
            Text("Your current plan includes one miner; this miner is outside that limit.")
        }
        .task {
            for await info in Purchases.shared.customerInfoStream {
                self.customerInfo = info
            }
        }
        .task {
            for await status in whatsNewTip.statusUpdates {
                await MainActor.run {
                    viewModel.handleWhatsNewTipStatus(status)
                }
            }
        }
    }

    @ViewBuilder
    private func detail(for feature: DeviceListFeature) -> some View {
        switch feature {
        case .miner(let ipAddress):
            DeviceSummaryView(
                dashboardViewModel: dashboardViewModel,
                deviceName: minerName(for: ipAddress),
                deviceIP: ipAddress,
                poolName: viewModel.deviceMetrics[ipAddress]?.poolURL,
                onMinerDeleted: { deletedIPAddress in
                    viewModel.deleteDevices(withIPAddresses: Set([deletedIPAddress]))
                }
            )
        case .fleetRecap:
            WeeklyRecapView(
                scope: .fleet(
                    devices: viewModel.savedDevices.map { device in
                        WeeklyRecapFleetDevice(
                            id: device.ipAddress,
                            name: minerName(for: device.ipAddress),
                            poolName: viewModel.deviceMetrics[device.ipAddress]?.poolURL,
                            currentHashrate: viewModel.deviceMetrics[device.ipAddress]?.hashrate
                                ?? 0
                        )
                    }
                )
            )
        }
    }

    /// Resolves the display name from current data, so navigating by IP address never
    /// shows a name captured when the miner was selected.
    private func minerName(for ipAddress: String) -> String {
        viewModel.deviceMetrics[ipAddress]?.hostname
            ?? viewModel.savedDevices.first { $0.ipAddress == ipAddress }?.name
            ?? ipAddress
    }

    private var sidebar: some View {
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
                            navigation.select(.fleetRecap)
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
                    sortOption: viewModel.deviceGridSortOption,
                    subscriptionAccessPolicy: subscriptionAccessPolicy
                )
            }
        }
        .navigationTitle("Traxe")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !viewModel.savedDevices.isEmpty {
                    Button(viewModel.isEditMode ? "Done" : "Edit") {
                        withAnimation {
                            viewModel.isEditMode.toggle()
                        }
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if viewModel.savedDevices.count < addDeviceLimit {
                        showingAddSheet = true
                    } else {
                        // User is at or over their limit (or has 0 devices but somehow no free slot logic triggered, though current logic covers this), show paywall
                        showingPaywallSheet = true
                    }
                } label: {
                    Label("Add Miner", systemImage: "plus")
                }
                .tint(Color.traxeGold)
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
            navigation.select(.miner(ipAddress: device.ipAddress))
        } else {
            // Always use the dashboard error message if available, even if empty
            connectionErrorMessage =
                dashboardViewModel.errorMessage.isEmpty
                ? "Could not connect to the miner at \(device.ipAddress). Please check the IP and network."
                : dashboardViewModel.errorMessage

            connectionErrorDeviceInfo = dashboardViewModel.errorDeviceInfo
            showConnectionErrorAlert = true
            navigation.clearSelection()
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
            from: DeviceMetrics(
                hashrate: 5100,
                temperature: 61,
                power: 600,
                bestDifficulty: 4_070,
                hostname: "nerdqaxe++"
            )
        ),
        "192.168.1.102": CachedDeviceMetrics(
            from: DeviceMetrics(
                hashrate: 721,
                temperature: 65,
                power: 620,
                bestDifficulty: 598.7,
                hostname: "bitaxe"
            )
        ),
        "192.168.1.103": CachedDeviceMetrics(
            from: DeviceMetrics(
                hashrate: 450,
                temperature: 68,
                power: 610,
                bestDifficulty: 412.2,
                hostname: "octaxe"
            )
        ),
        "192.168.1.104": CachedDeviceMetrics(
            from: DeviceMetrics(
                hashrate: 3800,
                temperature: 72,
                power: 620,
                bestDifficulty: 1_200,
                hostname: "lucky"
            )
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

    // DeviceListView owns its own NavigationSplitView, exactly as the app scene uses it.
    // Important: do not pass mockUserDefaults; use app group store
    return DeviceListView(
        dashboardViewModel: previewDashboardVM,
        navigateToDeviceList: .constant(true)
    )
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

    return DeviceListView(
        dashboardViewModel: previewDashboardVM,
        navigateToDeviceList: .constant(true),
        mockUserDefaults: groupDefaults
    )
    .modelContainer(container)
}

#Preview("Fleet Recap Selected") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = makeDeviceListPreviewContainer(config: config)
    let previewDashboardVM = DashboardViewModel(modelContext: container.mainContext)

    let groupDefaults = previewGroupDefaults()
    let devices = [
        SavedDevice(name: "nerdqaxe++", ipAddress: "192.168.1.101"),
        SavedDevice(name: "bitaxe", ipAddress: "192.168.1.102"),
    ]
    if let encodedDevices = try? JSONEncoder().encode(devices) {
        groupDefaults.set(encodedDevices, forKey: "savedDevices")
    }

    // Seeding the navigation state shows the detail column the same way a selection
    // does at runtime: beside the dashboard when wide, pushed when collapsed.
    return DeviceListView(
        dashboardViewModel: previewDashboardVM,
        navigateToDeviceList: .constant(true),
        mockUserDefaults: groupDefaults,
        initialNavigationState: DeviceListNavigationState(
            selectedFeature: .fleetRecap,
            preferredCompactColumn: .detail
        )
    )
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
