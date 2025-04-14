import SwiftData
import SwiftUI

struct HostnameConfigurationView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) var dismiss

    @State private var localHostname: String = ""
    @State private var showErrorAlert: Bool = false

    var body: some View {
        Form {
            Section("Device Configuration") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hostname".uppercased())
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("bitaxe", text: $localHostname)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                    Text("The device name shown on your network and in the app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }

            Section {
                Button("Save") {
                    viewModel.hostname = localHostname

                    Task {
                        let success = await viewModel.saveHostnameConfiguration()
                        if success {
                            dismiss()
                        } else {
                            showErrorAlert = true
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
        .navigationTitle("Hostname Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            localHostname = viewModel.hostname
        }
        .alert("Save Error", isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(viewModel.hostnameConfigurationError ?? "An unknown error occurred. Please try again.")
        }
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

            return NavigationView {
                HostnameConfigurationView(viewModel: previewViewModel)
            }
        }
    }
#endif