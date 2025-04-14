import RevenueCat
import SwiftData
import SwiftUI
import WidgetKit

struct DeviceListView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = DeviceListViewModel()
    @StateObject var dashboardViewModel: DashboardViewModel
    @Binding var navigateToDeviceList: Bool
    @State private var navigateToDashboard = false
    @State private var selectedDeviceIP: String? = nil
    @State private var showConnectionErrorAlert = false
    @State private var connectionErrorMessage = ""
    @State private var showingAddSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var indexSetToDelete: IndexSet? = nil
    @State private var showingPaywallSheet = false
    @State private var customerInfo: CustomerInfo? = nil
    @Namespace private var heroNamespace

    var body: some View {
        VStack {
            if viewModel.savedDevices.count > 1 {
                AggregatedStatsHeader(viewModel: viewModel)
                    .padding(.horizontal)
            }

            if !viewModel.savedDevices.isEmpty {
                List {
                    Section {
                        ForEach(viewModel.savedDevices) { device in
                            DeviceRow(device: device)
                                .contentShape(Rectangle())
                                .matchedTransitionSource(id: device.ipAddress, in: heroNamespace)
                                .onTapGesture {
                                    selectedDeviceIP = device.ipAddress
                                    Task {
                                        await connectAndNavigate(to: device)
                                    }
                                }
                        }
                        .onDelete { indexSet in
                            indexSetToDelete = indexSet
                            showingDeleteConfirmation = true
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .refreshable {
                    viewModel.loadDevices()
                }
            }
        }
        .navigationTitle("Traxe")
        .toolbar {
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
        .navigationDestination(isPresented: $navigateToDashboard) {
            if let selectedIP = selectedDeviceIP {
                DashboardView(viewModel: dashboardViewModel)
                    .navigationTransition(.zoom(sourceID: selectedIP, in: heroNamespace))
            } else {
                Text("Error: No device selected")
            }
        }
        .alert("Connection Failed", isPresented: $showConnectionErrorAlert) {
            Button("OK") {}
        } message: {
            Text(connectionErrorMessage)
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
    }

    private func connectAndNavigate(to device: SavedDevice) async {
        showConnectionErrorAlert = false
        connectionErrorMessage = ""

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
            navigateToDashboard = true
        } else {
            connectionErrorMessage =
                dashboardViewModel.errorMessage.isEmpty
                ? "Could not connect to the device at \(device.ipAddress). Please check the IP and network."
                : dashboardViewModel.errorMessage
            showConnectionErrorAlert = true
            navigateToDashboard = false
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: HistoricalDataPoint.self, configurations: config)
    let previewDashboardVM = DashboardViewModel(modelContext: container.mainContext)

    let previewDeviceListVM = DeviceListViewModel()
    previewDeviceListVM.savedDevices = [
        SavedDevice(name: "Living Room", ipAddress: "192.168.1.101"),
        SavedDevice(name: "Office", ipAddress: "192.168.1.102"),
    ]

    return DeviceListView(
        dashboardViewModel: previewDashboardVM,
        navigateToDeviceList: .constant(true)
    )
    .environmentObject(previewDeviceListVM)
    .modelContainer(container)
}

#Preview {
    DeviceRow(
        device: SavedDevice(name: "device", ipAddress: "1.1.1.1")
    )
}
