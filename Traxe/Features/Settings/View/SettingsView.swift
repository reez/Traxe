import SwiftData
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showingRestartConfirmation = false

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                ConnectionSection(
                    ipAddress: $viewModel.bitaxeIPAddress,
                    onSubmit: viewModel.saveSettings,
                    isConnected: viewModel.isConnected
                )

                Section("Firmware") {
                    HStack {
                        Text("Firmware Version")
                        Spacer()
                        if viewModel.currentVersion != "Unknown" {
                            Text(viewModel.currentVersion)
                                .foregroundColor(.secondary)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }

                DangerZoneSection(onRestart: { showingRestartConfirmation = true })

                Section {
                    NavigationLink("Advanced Settings") {
                        AdvancedSettingsView(viewModel: viewModel)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.saveSettings()
                        dismiss()
                    }
                    .foregroundColor(.traxeGold)
                }
            }
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
        .onAppear {
            viewModel.loadSettings()
        }
    }
}

#Preview {
    let previewContainer: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: HistoricalDataPoint.self, configurations: config)
        } catch {
            fatalError("Failed to create preview container: \(error)")
        }
    }()

    let previewSharedDefaults = UserDefaults(
        suiteName: SettingsViewModel.sharedUserDefaultsSuiteName
    )

    let previewViewModel = SettingsViewModel(
        sharedUserDefaults: previewSharedDefaults,
        modelContext: previewContainer.mainContext
    )

    SettingsView(viewModel: previewViewModel)
        .modelContainer(previewContainer)
}
