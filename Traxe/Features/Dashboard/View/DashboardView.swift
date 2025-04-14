import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject var viewModel: DashboardViewModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTimeRange: TimeRange = .lastHour
    @State private var showingSettings = false
    @State private var showStatusText = false

    init(viewModel: DashboardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                topMetricsGrid
                    .padding(.top, 16)
                individualMetrics
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.primary)
                        .font(.caption)
                        .fontWeight(.bold)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.primary)
                }
            }
        }
        .refreshable {
            await viewModel.refreshData()
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
        .alert("Error", isPresented: $viewModel.showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .task {
            await viewModel.connectIfNeeded()
            viewModel.fetchHistoricalData(timeRange: selectedTimeRange)
        }
    }

    private var topMetricsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible())
            ],
            spacing: 16
        ) {
            MetricCard(
                title: "Hash Rate",
                value: viewModel.connectionState == .connected
                    ? viewModel.formattedHashRate : "---",
                unit: viewModel.connectionState == .connected
                    ? viewModel.formattedHashRateUnit : "---",
                icon: "bolt.fill",
                historicalData: viewModel.connectionState == .connected
                    ? viewModel.historicalData : [],
                historicalDataKey: \.hashrate,
                chartStyle: .bars,
                isConnected: viewModel.connectionState == .connected
            )

            MetricCard(
                title: "Uptime",
                value: viewModel.connectionState == .connected
                    ? viewModel.uptime : "---",
                unit: "",
                icon: "clock.fill",
                isConnected: viewModel.connectionState == .connected
            )

            MetricCard(
                title: "Shares",
                value: viewModel.connectionState == .connected
                    ? viewModel.formattedSharesAccepted : "---",
                unit: viewModel.connectionState == .connected
                    ? String(
                        format: "(%d rejected)",
                        viewModel.currentMetrics.sharesRejected
                    ) : "",
                icon: "paperplane.fill",
                isConnected: viewModel.connectionState == .connected
            )

            MetricCard(
                title: "Efficiency",
                value: viewModel.connectionState == .connected
                    ? String(format: "%.2f", viewModel.currentMetrics.efficiency) : "---",
                unit: "W/Th",
                icon: "hand.thumbsup.fill",
                isConnected: viewModel.connectionState == .connected
            )

            MetricCard(
                title: "Best Difficulty",
                value: viewModel.connectionState == .connected
                    ? viewModel.formattedBestDifficulty.value
                    : "---",
                unit: viewModel.connectionState == .connected
                    ? viewModel.formattedBestDifficulty.unit
                    : "",
                icon: "star.fill",
                isConnected: viewModel.connectionState == .connected
            )
        }
        .padding(.horizontal)
    }

    private var individualMetrics: some View {
        Group {
            MetricCard(
                title: "Power",
                value: viewModel.connectionState == .connected
                    ? String(format: "%.1f", viewModel.currentMetrics.power) : "---",
                unit: "W",
                icon: nil,
                progress: viewModel.connectionState == .connected
                    ? (value: viewModel.currentMetrics.power, maxValue: 20) : nil,
                isConnected: viewModel.connectionState == .connected
            )
            .padding(.horizontal)

            MetricCard(
                title: "Input Voltage",
                value: viewModel.connectionState == .connected
                    ? String(format: "%.1f", viewModel.currentMetrics.inputVoltage) : "---",
                unit: "V",
                icon: nil,
                progress: viewModel.connectionState == .connected
                    ? (value: viewModel.currentMetrics.inputVoltage, maxValue: 6) : nil,
                isConnected: viewModel.connectionState == .connected
            )
            .padding(.horizontal)

            MetricCard(
                title: "ASIC Voltage Requested",
                value: viewModel.connectionState == .connected
                    ? String(format: "%.1f", viewModel.currentMetrics.asicVoltage) : "---",
                unit: "V",
                icon: nil,
                progress: viewModel.connectionState == .connected
                    ? (value: viewModel.currentMetrics.asicVoltage, maxValue: 2) : nil,
                isConnected: viewModel.connectionState == .connected
            )
            .padding(.horizontal)

            MetricCard(
                title: "ASIC Temperature",
                value: viewModel.connectionState == .connected
                    ? String(format: "%.0f", viewModel.currentMetrics.temperature) : "---",
                unit: "°C",
                icon: nil,
                progress: viewModel.connectionState == .connected
                    ? (value: viewModel.currentMetrics.temperature, maxValue: 100) : nil,
                isConnected: viewModel.connectionState == .connected
            )
            .padding(.horizontal)

            MetricCard(
                title: "Fan",
                value: viewModel.connectionState == .connected
                    ? String(format: "%.0f", Double(viewModel.currentMetrics.fanSpeedPercent))
                    : "---",
                unit: "%",
                icon: nil,
                progress: viewModel.connectionState == .connected
                    ? (value: Double(viewModel.currentMetrics.fanSpeedPercent), maxValue: 100)
                    : nil,
                isConnected: viewModel.connectionState == .connected
            )
            .padding(.horizontal)

            MetricCard(
                title: "ASIC Frequency",
                value: viewModel.connectionState == .connected
                    ? String(format: "%.0f", viewModel.currentMetrics.frequency) : "---",
                unit: "MHz",
                icon: nil,
                progress: viewModel.connectionState == .connected
                    ? (value: viewModel.currentMetrics.frequency, maxValue: 600) : nil,
                isConnected: viewModel.connectionState == .connected
            )
            .padding(.horizontal)

            MetricCard(
                title: "ASIC Voltage Measured",
                value: viewModel.connectionState == .connected
                    ? String(format: "%.1f", viewModel.currentMetrics.measuredVoltage) : "---",
                unit: "V",
                icon: nil,
                progress: viewModel.connectionState == .connected
                    ? (value: viewModel.currentMetrics.measuredVoltage, maxValue: 2) : nil,
                isConnected: viewModel.connectionState == .connected
            )
            .padding(.horizontal)
        }
    }

    private var connectionStatusIconName: String {
        switch viewModel.connectionState {
        case .disconnected:
            return "antenna.radiowaves.left.and.right.slash"
        case .connecting:
            return "antenna.radiowaves.left.and.right"
        case .connected:
            return "antenna.radiowaves.left.and.right"
        }
    }

    //    private var connectionStatusColor: Color {
    //        switch viewModel.connectionState {
    //        case .disconnected:
    //            return .red
    //        case .connecting:
    //            return .secondary  //.orange
    //        case .connected:
    //            return .green
    //        }
    //    }

    //    private var connectionStatusText: String {
    //        switch viewModel.connectionState {
    //        case .disconnected:
    //            return "Disconnected"
    //        case .connecting:
    //            return "Connecting..."
    //        case .connected:
    //            return "Connected"
    //        }
    //    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: HistoricalDataPoint.self, configurations: config)

    return NavigationView {
        DashboardView(
            viewModel: DashboardViewModel(
                modelContext: container.mainContext
            )
        )
        .modelContainer(container)
    }
}
