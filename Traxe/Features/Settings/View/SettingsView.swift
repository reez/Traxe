import StoreKit
import SwiftData
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showingRestartConfirmation = false
    @State private var isAIEnabled = UserDefaults.standard.bool(forKey: "ai_enabled")

    @Environment(\.dismiss) var dismiss
    @Environment(\.requestReview) var requestReview

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

                    Section {
                        NavigationLink("Miner Configuration") {
                            AdvancedSettingsView(viewModel: viewModel)
                        }
                    } header: {
                        Text("Advanced")
                    }

                    ConnectionSection(
                        ipAddress: $viewModel.bitaxeIPAddress,
                        onSubmit: viewModel.saveSettings,
                        isConnected: viewModel.isConnected
                    )

                    Section("Firmware") {
                        HStack {
                            Text("Version")
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
                            Toggle("Miner Summary", isOn: $isAIEnabled)
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

                    //                    Section {
                    //                        NavigationLink("Configuration") {
                    //                            AdvancedSettingsView(viewModel: viewModel)
                    //                        }
                    //                    } header: {
                    //                        Text("Advanced")
                    //                    }

                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Loving the app? A nice review would make my day!")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button {
                                requestReview()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "heart.fill")
                                        .foregroundStyle(.pink)
                                    Text("Leave a Review")
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Having issues? Reach out and I'll make it right.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button {
                                if let url = supportEmailURL {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "envelope.fill")
                                        .foregroundStyle(.secondary)
                                    Text("Email Support")
                                        .foregroundStyle(.primary)
                                }
                            }
                            .tint(.secondary)
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    } header: {
                        Text("Feedback")
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

extension SettingsView {
    fileprivate var supportEmailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "ramsden.matthew@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Traxe - Support Issue")
        ]
        return components.url
    }
}
