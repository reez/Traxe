import SwiftData
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showingRestartConfirmation = false
    @State private var isAIEnabled = UserDefaults.standard.bool(forKey: "ai_enabled")

    @Environment(\.dismiss) var dismiss

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
                                    .animation(nil, value: viewModel.currentVersion)
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }

                    DangerZoneSection(onRestart: { showingRestartConfirmation = true })

                    if #available(iOS 18.0, macOS 15.0, *) {
                        Section {
                            Toggle("Summaries", isOn: $isAIEnabled)
                                .tint(.accentColor)
                                .onChange(of: isAIEnabled) { _, newValue in
                                    UserDefaults.standard.set(newValue, forKey: "ai_enabled")
                                }
                        } header: {
                            Text("Features")
                        } footer: {
                            Text(
                                "Uses [Apple Intelligence](https://www.apple.com/apple-intelligence/)."
                            )
                        }
                    }

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
                        //                    .foregroundColor(.traxeGold)
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
