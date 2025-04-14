import SwiftData
import SwiftUI

struct PoolConfigurationView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) var dismiss

    @State private var localStratumURL: String = ""
    @State private var localStratumPortString: String = ""
    @State private var localStratumUser: String = ""
    @State private var showErrorAlert: Bool = false

    var body: some View {
        Form {
            Section("Pool Configuration") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stratum Host".uppercased())
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("NA.lincoin.com", text: $localStratumURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                    Text("Do not include 'stratum+tcp://' or port.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stratum Port".uppercased())
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("3333", text: $localStratumPortString)
                        .keyboardType(.numberPad)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stratum User".uppercased())
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("pod256.traxe", text: $localStratumUser)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                }
            }

            Section {
                Button("Save") {
                    viewModel.stratumURL = localStratumURL
                    viewModel.stratumPortString = localStratumPortString
                    viewModel.stratumUser = localStratumUser

                    Task {
                        let success = await viewModel.savePoolConfiguration()
                        if success {
                            dismiss()
                        } else {
                            showErrorAlert = true
                        }
                    }
                }
                .disabled(viewModel.isUpdatingPoolConfiguration)

                if viewModel.isUpdatingPoolConfiguration {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Pool Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            localStratumURL = viewModel.stratumURL
            localStratumPortString = viewModel.stratumPortString
            localStratumUser = viewModel.stratumUser
        }
        .alert("Save Error", isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(viewModel.poolConfigurationError ?? "An unknown error occurred. Please try again.")
        }
    }
}

#if DEBUG
    struct PoolConfigurationView_Previews: PreviewProvider {
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
            previewViewModel.stratumURL = "stratum.slushpool.com"
            previewViewModel.stratumPortString = "3333"
            previewViewModel.stratumUser = "testUser.worker1"

            return NavigationView {
                PoolConfigurationView(viewModel: previewViewModel)
            }
        }
    }
#endif
