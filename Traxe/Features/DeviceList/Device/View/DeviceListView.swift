import RevenueCat
import SwiftData
import SwiftUI
import WidgetKit

struct DeviceListView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: DeviceListViewModel
    @StateObject var dashboardViewModel: DashboardViewModel
    @Binding var navigateToDeviceList: Bool

    init(
        dashboardViewModel: DashboardViewModel,
        navigateToDeviceList: Binding<Bool>,
        mockUserDefaults: UserDefaults? = nil
    ) {
        self._dashboardViewModel = StateObject(wrappedValue: dashboardViewModel)
        self._navigateToDeviceList = navigateToDeviceList
        if let mockDefaults = mockUserDefaults {
            self._viewModel = StateObject(wrappedValue: DeviceListViewModel(defaults: mockDefaults))
        } else {
            self._viewModel = StateObject(wrappedValue: DeviceListViewModel())
        }
    }
    @State private var navigateToSummary = false
    @State private var selectedDevice: SavedDevice? = nil
    @State private var showConnectionErrorAlert = false
    @State private var connectionErrorMessage = ""
    @State private var connectionErrorDeviceInfo = ""
    @State private var showingAddSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var indexSetToDelete: IndexSet? = nil
    @State private var showingPaywallSheet = false
    @State private var showingSubscriptionExpiredAlert = false
    @State private var customerInfo: CustomerInfo? = nil

    private var deviceGridView: some View {
        LazyVStack(spacing: 40) {
            // Add some top spacing to allow for proper scroll detection
            Spacer().frame(height: 10)

            if viewModel.savedDevices.count > 1 {
                AggregatedStatsHeader(viewModel: viewModel)
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("Miners")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.horizontal)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ],
                    spacing: 12
                ) {
                    ForEach(Array(viewModel.savedDevices.enumerated()), id: \.element.id) {
                        index,
                        device in
                        deviceCardView(for: device, at: index)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 40)
    }

    private func deviceCardView(for device: SavedDevice, at index: Int) -> some View {
        let proIsActive = self.customerInfo?.entitlements["Pro"]?.isActive == true
        let miners5IsActive = self.customerInfo?.entitlements["Miners_5"]?.isActive == true
        let isAccessible =
            proIsActive || (miners5IsActive && index < 5)
            || (!proIsActive && !miners5IsActive && index == 0)

        let metrics = viewModel.deviceMetrics[device.ipAddress]
        let hashRate = metrics?.hashrate ?? 0.0
        let displayValue = hashRate >= 1000 ? hashRate / 1000 : hashRate
        let displayUnit = hashRate >= 1000 ? "TH/s" : "GH/s"
        // While refreshing, keep devices styled as reachable.
        // After refresh completes, gray only devices that did not respond (not in reachableIPs).
        let isReachable =
            viewModel.isLoadingAggregatedStats
            || viewModel.reachableIPs.contains(device.ipAddress)
            // In previews we seed cached metrics only; treat those as reachable for styling
            || (ProcessInfo.isPreview && metrics != nil)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(metrics?.hostname ?? device.name)
                        .font(.caption)
                        .bold()
                        .lineLimit(1)
                        .foregroundStyle(isReachable ? .primary : .secondary)

                    Text(device.ipAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Only show lock icon if we have data AND subscription info loaded AND user doesn't have access
                // Don't show lock when: data loading, subscription loading, or user has access
                if !isAccessible && metrics != nil && customerInfo != nil {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Spacer()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metrics != nil ? String(format: "%.1f", displayValue) : "---")
                        .font(.title)
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                        .contentTransition(.numericText())
                        .animation(.spring, value: hashRate)
                        .redacted(reason: metrics == nil ? .placeholder : [])
                        .foregroundStyle(isReachable ? .primary : .secondary)

                    Text(displayUnit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding()
        //        .background(Color(.secondarySystemBackground))
        //        .background(
        //            LinearGradient(
        //                colors: [
        //                    Color(.tertiarySystemBackground),
        //                    Color(.secondarySystemBackground)
        //                ],
        //                startPoint: .bottom,
        //                endPoint: .top
        //            )
        //        )
        .background(Color(.secondarySystemBackground))
        //        .background(
        //            LinearGradient(
        //                colors: [
        //                    Color(.tertiarySystemBackground),
        //                    Color(.secondarySystemBackground)
        //                ],
        //                startPoint: .top,
        //                endPoint: .bottom
        //            )
        //        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                //                .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(
            color: Color.primary.opacity(0.08),
            radius: 8,
            x: 0,
            y: 4
        )
        .contentShape(Rectangle())
        .onTapGesture {
            handleDeviceTap(device: device, isAccessible: isAccessible)
        }
    }

    private func handleDeviceTap(device: SavedDevice, isAccessible: Bool) {
        if isAccessible {
            selectedDevice = device
            Task {
                await connectAndNavigate(to: device)
            }
        } else {
            let proIsActive = self.customerInfo?.entitlements["Pro"]?.isActive == true
            let miners5IsActive = self.customerInfo?.entitlements["Miners_5"]?.isActive == true
            if !proIsActive && !miners5IsActive {
                showingSubscriptionExpiredAlert = true
            }
        }
    }

    private func editModeRow(for device: SavedDevice, at index: Int) -> some View {
        HStack(alignment: .center) {
            Text("\(index + 1)")
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(index < 9 ? .primary : .secondary)
                .frame(width: 30)

            VStack(alignment: .leading) {
                Text(viewModel.deviceMetrics[device.ipAddress]?.hostname ?? device.name)
                    .font(.headline)
                Text(device.ipAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let metrics = viewModel.deviceMetrics[device.ipAddress] {
                    Text(
                        "\(String(format: "%.1f", metrics.hashrate >= 1000 ? metrics.hashrate / 1000 : metrics.hashrate)) \(metrics.hashrate >= 1000 ? "TH/s" : "GH/s")"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .font(.title2)
        }
        .padding(.vertical, 8)
    }

    private var editModeOverlay: some View {
        VStack {
            //            HStack {
            //                Text("Drag to reorder")
            //                    .italic()
            //                    .padding(.leading)
            //                Spacer()
            //            }
            //            .padding(.top)

            List {
                ForEach(Array(viewModel.savedDevices.enumerated()), id: \.element.id) {
                    index,
                    device in
                    editModeRow(for: device, at: index)
                }
                .onMove(perform: viewModel.reorderDevices)
                .onDelete(perform: viewModel.deleteDevice)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
        .transition(.opacity)
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
                VStack(spacing: 0) {
                    deviceGridView
                }
            }
            .refreshable {
                await viewModel.updateAggregatedStats()
            }
            .allowsHitTesting(!viewModel.isEditMode)

            if viewModel.isEditMode {
                editModeOverlay
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
                    let proIsActive = self.customerInfo?.entitlements["Pro"]?.isActive == true
                    let miners5IsActive =
                        self.customerInfo?.entitlements["Miners_5"]?.isActive == true

                    let deviceLimit: Int
                    if proIsActive {
                        deviceLimit = Int.max  // Unlimited for Pro Monthly
                    } else if miners5IsActive {
                        deviceLimit = 5  // 5 for Miners_5 (total, includes the 1 free)
                    } else {
                        deviceLimit = 1  // 1 for free tier
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
                Text("Error: No device selected")
            }
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
        .alert("Delete Device", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let indexSet = indexSetToDelete {
                    viewModel.deleteDevice(at: indexSet)
                }
                indexSetToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                indexSetToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete this device?")
        }
        .alert("Monthly Subscription Expired", isPresented: $showingSubscriptionExpiredAlert) {
            Button("OK") {}
        } message: {
            Text("Your monthly subscription has expired. Please renew to access this device.")
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
                ? "Could not connect to the device at \(device.ipAddress). Please check the IP and network."
                : dashboardViewModel.errorMessage

            connectionErrorDeviceInfo = dashboardViewModel.errorDeviceInfo
            showConnectionErrorAlert = true
            navigateToSummary = false
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: HistoricalDataPoint.self, configurations: config)
    let previewDashboardVM = DashboardViewModel(modelContext: container.mainContext)

    // Use the app group defaults so the view model and cache read the same store
    let groupDefaults = UserDefaults(suiteName: "group.matthewramsden.traxe")!

    // Seed devices
    let devices = [
        SavedDevice(name: "nerdqaxe++", ipAddress: "192.168.1.101"),
        SavedDevice(name: "bitaxe", ipAddress: "192.168.1.102"),
        SavedDevice(name: "octaxe", ipAddress: "192.168.1.103"),
        SavedDevice(name: "lucky", ipAddress: "192.168.1.104"),
    ]
    let devEncoder = JSONEncoder()
    groupDefaults.set(try! devEncoder.encode(devices), forKey: "savedDevices")

    // Enable AI features for previews
    UserDefaults.standard.set(true, forKey: "ai_enabled")

    // Seed cached device metrics so cards and totals are populated (hashrate in GH/s)
    let cached: [String: CachedDeviceMetrics] = [
        "192.168.1.101": CachedDeviceMetrics(from: DeviceMetrics(hashrate: 5100, temperature: 61, power: 600, hostname: "nerdqaxe++")),
        "192.168.1.102": CachedDeviceMetrics(from: DeviceMetrics(hashrate: 721, temperature: 65, power: 620, hostname: "bitaxe")),
        "192.168.1.103": CachedDeviceMetrics(from: DeviceMetrics(hashrate: 450, temperature: 68, power: 610, hostname: "octaxe")),
        "192.168.1.104": CachedDeviceMetrics(from: DeviceMetrics(hashrate: 3800, temperature: 72, power: 620, hostname: "lucky")),
    ]
    let cacheEncoder = JSONEncoder(); cacheEncoder.dateEncodingStrategy = .iso8601
    groupDefaults.set(try! cacheEncoder.encode(cached), forKey: "cachedDeviceMetricsV1")

    // Seed a cached fleet AI summary so the preview doesn't need networking
    struct _FleetSummaryCacheEntry: Codable { let content: String; let generatedAt: Date; let deviceCount: Int }
    let summaryContent = "\(devices.count) devices producing a total of 10.1 TH/s, with a temperature range of 61-72°C, and consuming 2450W of power."
    let summaryEncoder = JSONEncoder(); summaryEncoder.dateEncodingStrategy = .iso8601
    groupDefaults.set(
        try! summaryEncoder.encode(_FleetSummaryCacheEntry(content: summaryContent, generatedAt: Date(), deviceCount: devices.count)),
        forKey: "cachedFleetAISummaryV1"
    )

    return NavigationView {
        // Important: do not pass mockUserDefaults; use app group store
        DeviceListView(
            dashboardViewModel: previewDashboardVM,
            navigateToDeviceList: .constant(true)
        )
    }
    .modelContainer(container)
}
