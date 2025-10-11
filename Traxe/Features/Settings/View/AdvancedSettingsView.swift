import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showingRestartConfirmation = false

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

            Form {
                FanControlSection(viewModel: viewModel)
                    .safeAreaPadding(.bottom, 10)
                Section("Network Configuration") {
                    NavigationLink("Pool Configuration") {
                        PoolConfigurationView(viewModel: viewModel)
                    }
                }

                Section("Miner Configuration") {
                    NavigationLink("Hostname") {
                        HostnameConfigurationView(viewModel: viewModel)
                    }
                }
            }
        }
        .navigationTitle("Advanced Settings")
        .alert("Restart Miner", isPresented: $showingRestartConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Restart", role: .destructive) {
                Task { await viewModel.restartDevice() }
            }
        } message: {
            Text(
                "Are you sure you want to restart the miner? This will temporarily stop mining operations."
            )
        }
    }
}
