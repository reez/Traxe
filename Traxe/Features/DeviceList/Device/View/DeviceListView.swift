import RevenueCat
import SwiftData
import SwiftUI
import WidgetKit

struct DeviceListView: View {
    @Environment(\.dismiss) var dismiss
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
    @State private var currentIndex = 0
    @State private var scrolledID: AnyHashable? = nil
    @Namespace private var heroNamespace

    private var totalItemCount: Int {
        viewModel.savedDevices.count + (viewModel.savedDevices.count > 1 ? 1 : 0)
    }

    private var deviceScrollView: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    if viewModel.savedDevices.count > 1 {
                        AggregatedStatsHeader(viewModel: viewModel)
                            .frame(width: geometry.size.width)
                            .id("total")
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let firstDevice = viewModel.savedDevices.first {
                                    withAnimation(.spring()) {
                                        scrolledID = firstDevice.id
                                    }
                                }
                            }
                    }

                    ForEach(Array(viewModel.savedDevices.enumerated()), id: \.element.id) {
                        index,
                        device in
                        deviceRowView(for: device, at: index)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .background(Color.clear)
                    }
                }
                .scrollTargetLayout()
            }
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolledID)
        .onChange(of: scrolledID) { _, newID in
            updateCurrentIndex(from: newID)
        }
        .refreshable {
            viewModel.loadDevices()
        }
    }

    private func deviceRowView(for device: SavedDevice, at index: Int) -> some View {
        let proIsActive = self.customerInfo?.entitlements["Pro"]?.isActive == true
        let miners5IsActive = self.customerInfo?.entitlements["Miners_5"]?.isActive == true
        let isAccessible =
            proIsActive || (miners5IsActive && index < 5)
            || (!proIsActive && !miners5IsActive && index == 0)

        return DeviceRow(
            device: device,
            isAccessible: isAccessible,
            deviceMetrics: viewModel.deviceMetrics[device.ipAddress]
        )
        .padding(.vertical, 8)
        .padding(.horizontal)
        .contentShape(Rectangle())
        .id(device.id)
        .matchedTransitionSource(id: device.ipAddress, in: heroNamespace)
        .onTapGesture {
            handleDeviceTap(device: device, isAccessible: isAccessible)
        }
        .contextMenu {
            Button(role: .destructive) {
                if let idx = viewModel.savedDevices.firstIndex(of: device) {
                    indexSetToDelete = IndexSet(integer: idx)
                    showingDeleteConfirmation = true
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
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

    private func updateCurrentIndex(from newID: AnyHashable?) {
        guard let id = newID else { return }

        if id as? String == "total" {
            currentIndex = 0
        } else if let deviceID = id as? UUID,
            let deviceIndex = viewModel.savedDevices.firstIndex(where: { $0.id == deviceID })
        {
            currentIndex = viewModel.savedDevices.count > 1 ? deviceIndex + 1 : deviceIndex
        }
    }

    private var visibleDotRange: Range<Int> {
        let maxDots = 6
        let halfRange = maxDots / 2

        if totalItemCount <= maxDots {
            return 0..<totalItemCount
        }

        let start = max(0, currentIndex - halfRange)
        let end = min(totalItemCount, start + maxDots)
        let adjustedStart = max(0, end - maxDots)

        return adjustedStart..<end
    }

    private var pageIndicator: some View {
        Group {
            if totalItemCount > 1 {
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        ForEach(visibleDotRange, id: \.self) { index in
                            Circle()
                                .fill(
                                    index == currentIndex
                                        ? Color.primary : Color.primary.opacity(0.3)
                                )
                                .frame(width: 6, height: 6)
                                .animation(.easeInOut(duration: 0.2), value: currentIndex)
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.spring()) {
                                        jumpToPage(index)
                                    }
                                }
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: visibleDotRange)

                    Text(devicePositionText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
    }

    private var devicePositionText: String {
        if currentIndex == 0 && viewModel.savedDevices.count > 1 {
            // On aggregated stats page
            return "\(viewModel.savedDevices.count)"
        } else {
            // On individual device page
            let deviceIndex = viewModel.savedDevices.count > 1 ? currentIndex : currentIndex + 1
            return "\(deviceIndex)/\(viewModel.savedDevices.count)"
        }
    }

    private func jumpToPage(_ index: Int) {
        if index == 0 && viewModel.savedDevices.count > 1 {
            // Jump to aggregated stats
            scrolledID = "total"
        } else {
            // Jump to specific device
            let deviceIndex = viewModel.savedDevices.count > 1 ? index - 1 : index
            if deviceIndex < viewModel.savedDevices.count {
                scrolledID = viewModel.savedDevices[deviceIndex].id
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
                    Text("\(String(format: "%.1f", metrics.hashrate >= 1000 ? metrics.hashrate / 1000 : metrics.hashrate)) \(metrics.hashrate >= 1000 ? "TH/s" : "GH/s")")
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
            HStack {
                Text("Drag to reorder")
                    .italic()
                    .padding(.leading)
                Spacer()
            }
            .padding(.top)
            
            List {
                ForEach(Array(viewModel.savedDevices.enumerated()), id: \.element.id) { index, device in
                    editModeRow(for: device, at: index)
                }
                .onMove(perform: viewModel.reorderDevices)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
        .transition(.opacity)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                deviceScrollView
                pageIndicator
            }
            .allowsHitTesting(!viewModel.isEditMode)
            
            if viewModel.isEditMode {
                editModeOverlay
            }
        }
        .padding(.all, 5)
        .navigationTitle("Traxe")
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
                }
            }
        }
        .onAppear {
            viewModel.loadDevices()
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
                DeviceSummaryView(dashboardViewModel: dashboardViewModel, deviceName: device.name)
                    .navigationTransition(.zoom(sourceID: device.ipAddress, in: heroNamespace))
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

    // Create mock UserDefaults with devices
    let mockDefaults = UserDefaults(suiteName: "preview")!
    let mockDevices = [
        SavedDevice(name: "Living Room", ipAddress: "192.168.1.101"),
        SavedDevice(name: "Office", ipAddress: "192.168.1.102"),
        SavedDevice(name: "Bedroom", ipAddress: "192.168.1.103"),
        SavedDevice(name: "Kitchen", ipAddress: "192.168.1.104"),
        SavedDevice(name: "Garage", ipAddress: "192.168.1.105"),
        SavedDevice(name: "Basement", ipAddress: "192.168.1.106"),
        SavedDevice(name: "Attic", ipAddress: "192.168.1.107"),
        SavedDevice(name: "Porch", ipAddress: "192.168.1.108"),
        SavedDevice(name: "Shed", ipAddress: "192.168.1.109"),
        SavedDevice(name: "Workshop", ipAddress: "192.168.1.110"),
        SavedDevice(name: "Server Room", ipAddress: "192.168.1.111"),
        SavedDevice(name: "Lab", ipAddress: "192.168.1.112"),
        SavedDevice(name: "Studio", ipAddress: "192.168.1.113"),
        SavedDevice(name: "Closet", ipAddress: "192.168.1.114"),
        SavedDevice(name: "Pantry", ipAddress: "192.168.1.115"),
        SavedDevice(name: "Balcony", ipAddress: "192.168.1.116"),
        SavedDevice(name: "Deck", ipAddress: "192.168.1.117"),
        SavedDevice(name: "Patio", ipAddress: "192.168.1.118"),
        SavedDevice(name: "Laundry", ipAddress: "192.168.1.119"),
        SavedDevice(name: "Mudroom", ipAddress: "192.168.1.120"),
    ]
    let encoder = JSONEncoder()
    if let data = try? encoder.encode(mockDevices) {
        mockDefaults.set(data, forKey: "savedDevices")
    }

    return NavigationView {
        DeviceListView(
            dashboardViewModel: previewDashboardVM,
            navigateToDeviceList: .constant(true),
            mockUserDefaults: mockDefaults
        )
    }
    .modelContainer(container)
}

#Preview("Accessible Device") {
    DeviceRow(
        device: SavedDevice(name: "device", ipAddress: "1.1.1.1"),
        isAccessible: true
    )
}

#Preview("Locked Device") {
    DeviceRow(
        device: SavedDevice(name: "device", ipAddress: "1.1.1.1"),
        isAccessible: false
    )
}
