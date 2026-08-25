import Observation
import SwiftUI

struct AdvancedSettingsView: View {
    @Bindable var viewModel: SettingsViewModel
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
                Section("Pools") {
                    NavigationLink("Pool Settings") {
                        if viewModel.supportsMultiPoolSettings {
                            PoolCatalogView(viewModel: viewModel)
                        } else {
                            PoolConfigurationView(viewModel: viewModel)
                        }
                    }
                }

                Section("Miner") {
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
                "Mining pauses while the miner restarts."
            )
        }
    }
}

#Preview("Advanced Settings") {
    let preview = PreviewFixtures.makeSettingsPreviewContext()

    NavigationStack {
        AdvancedSettingsView(viewModel: preview.viewModel)
    }
    .modelContainer(preview.container)
}
