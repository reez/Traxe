import Observation
import SwiftData
import SwiftUI

struct HostnameConfigurationView: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(\.dismiss) var dismiss

    @State private var localHostname: String = ""
    @State private var showErrorAlert: Bool = false

    var body: some View {
        Form {
            Section("Miner") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hostname".uppercased())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("bitaxe", text: $localHostname)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                    Text("The miner name shown on your network and in the app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }

            Section {
                Button("Save") {
                    viewModel.hostname = localHostname

                    Task {
                        let success = await viewModel.saveHostnameConfiguration()
                        if !success {
                            showErrorAlert = true
                        } else if !viewModel.needsRestartToApplySettings {
                            // Otherwise the restart alert below is showing; it dismisses.
                            dismiss()
                        }
                    }
                }
                .disabled(viewModel.isUpdatingHostname)

                if viewModel.isUpdatingHostname {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Hostname")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            localHostname = viewModel.hostname
        }
        .alert("Couldn’t Save Hostname", isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(
                viewModel.hostnameConfigurationError
                    ?? "An unknown error occurred. Please try again."
            )
        }
        .restartToApplySettingsAlert(
            isPresented: $viewModel.needsRestartToApplySettings,
            message:
                "The hostname is saved, but this miner only applies it when it restarts. Mining pauses while the miner restarts.",
            restart: { await viewModel.restartDevice() },
            dismiss: { dismiss() }
        )
    }
}

#if DEBUG
    struct HostnameConfigurationView_Previews: PreviewProvider {
        static var previews: some View {
            let previewContainer: ModelContainer = {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                do {
                    return try ModelContainer(for: HistoricalDataPoint.self, configurations: config)
                } catch {
                    fatalError("Failed to create preview container: \\(error)")
                }
            }()

            let previewSharedDefaults = UserDefaults(
                suiteName: SettingsViewModel.sharedUserDefaultsSuiteName
            )
            previewSharedDefaults?.removePersistentDomain(
                forName: SettingsViewModel.sharedUserDefaultsSuiteName
            )
            previewSharedDefaults?.set("192.168.1.100", forKey: "bitaxeIPAddress")

            let previewViewModel = SettingsViewModel(
                sharedUserDefaults: previewSharedDefaults,
                modelContext: previewContainer.mainContext
            )
            previewViewModel.hostname = "bitaxe"

            return NavigationStack {
                HostnameConfigurationView(viewModel: previewViewModel)
            }
        }
    }
#endif
