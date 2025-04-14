import SwiftData
import SwiftUI

struct DeviceSummaryView: View {
    @StateObject var dashboardViewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showingSettings = false
    let deviceName: String

    var body: some View {
        VStack(spacing: 20) {
            if dashboardViewModel.connectionState == .connected
                && !dashboardViewModel.historicalData.isEmpty
            {
                VStack(alignment: .center, spacing: 8) {
                    SparklineView(
                        data: dashboardViewModel.historicalData,
                        valueKey: \.hashrate,
                        style: .bars
                    )
                    .frame(height: 60)
                }
                .padding(.horizontal)
            }

            MetricsSummaryGrid(viewModel: dashboardViewModel)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundColor(.traxeGold)
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
        .onChange(of: showingSettings) { _, isShowing in
            if isShowing {
                dashboardViewModel.stopPolling()
            } else {
                dashboardViewModel.startPollingIfConnected()
            }
        }
        .task {
            await dashboardViewModel.connectIfNeeded()
            dashboardViewModel.fetchHistoricalData(timeRange: .lastHour)
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: HistoricalDataPoint.self, configurations: config)
    let previewViewModel = DashboardViewModel(modelContext: container.mainContext)

    return NavigationStack {
        DeviceSummaryView(dashboardViewModel: previewViewModel, deviceName: "Test Device")
    }
}
