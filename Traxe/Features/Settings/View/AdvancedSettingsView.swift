import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showingRestartConfirmation = false

    var body: some View {
        Form {
            FanControlSection(viewModel: viewModel)
                .safeAreaPadding(.bottom, 10)
            Section("Network Configuration") {
                NavigationLink("Pool Configuration") {
                    PoolConfigurationView(viewModel: viewModel)
                }
            }
        }
        .navigationTitle("Advanced Settings")
        .alert("Restart Device", isPresented: $showingRestartConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Restart", role: .destructive) {
                Task { await viewModel.restartDevice() }
            }
        } message: {
            Text(
                "Are you sure you want to restart the device? This will temporarily stop mining operations."
            )
        }
    }
}
