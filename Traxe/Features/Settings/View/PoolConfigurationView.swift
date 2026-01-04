import SwiftData
import SwiftUI

struct PoolConfigurationView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedPoolIndex: Int = 0
    @State private var localPrimaryStratumURL: String = ""
    @State private var localPrimaryStratumPortString: String = ""
    @State private var localPrimaryStratumUser: String = ""
    @State private var localSecondaryStratumURL: String = ""
    @State private var localSecondaryStratumPortString: String = ""
    @State private var localSecondaryStratumUser: String = ""
    @State private var localPoolBalance: Double = 50
    @State private var localPoolMode: Int = 0
    @State private var showErrorAlert: Bool = false

    private var localIsDualPool: Bool {
        localPoolMode == 1
    }

    private var poolSegmentTitles: [String] {
        localIsDualPool ? ["Pool 1", "Pool 2"] : ["Primary", "Fallback"]
    }

    private var poolBalanceTitle: String {
        let primary = Int(localPoolBalance.rounded())
        let secondary = max(0, 100 - primary)
        return "Pool Balance (\(primary)% / \(secondary)%)"
    }

    private var activeStratumURL: Binding<String> {
        selectedPoolIndex == 0 ? $localPrimaryStratumURL : $localSecondaryStratumURL
    }

    private var activeStratumPortString: Binding<String> {
        selectedPoolIndex == 0 ? $localPrimaryStratumPortString : $localSecondaryStratumPortString
    }

    private var activeStratumUser: Binding<String> {
        selectedPoolIndex == 0 ? $localPrimaryStratumUser : $localSecondaryStratumUser
    }

    var body: some View {
        Form {
            Section("Pool Configuration") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pool Mode".uppercased())
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Picker("Pool Mode", selection: $localPoolMode) {
                        Text("Failover").tag(0)
                        Text("Dual Pool").tag(1)
                    }
                    .pickerStyle(.menu)
                    Text("Changing pool mode may require a device restart.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                if localIsDualPool {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(poolBalanceTitle.uppercased())
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Slider(value: $localPoolBalance, in: 1...99, step: 1)
                        Text(
                            "Distributes jobs between the primary and secondary pool, e.g., 70/30."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        if Int(localPoolBalance.rounded()) == 1
                            || Int(localPoolBalance.rounded()) == 99
                        {
                            Text(
                                "Very low ratios can make pool hashrate estimates inaccurate."
                            )
                            .font(.caption)
                            .italic()
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Picker("Pool", selection: $selectedPoolIndex) {
                    ForEach(0..<poolSegmentTitles.count, id: \.self) { index in
                        Text(poolSegmentTitles[index]).tag(index)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Stratum Host".uppercased())
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("NA.lincoin.com", text: activeStratumURL)
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
                    TextField("3333", text: activeStratumPortString)
                        .keyboardType(.numberPad)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stratum User".uppercased())
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("pod256.traxe", text: activeStratumUser)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                }
            }

            Section {
                Button("Save") {
                    viewModel.stratumURL = localPrimaryStratumURL
                    viewModel.stratumPortString = localPrimaryStratumPortString
                    viewModel.stratumUser = localPrimaryStratumUser
                    viewModel.fallbackStratumURL = localSecondaryStratumURL
                    viewModel.fallbackStratumPortString = localSecondaryStratumPortString
                    viewModel.fallbackStratumUser = localSecondaryStratumUser
                    viewModel.poolBalance = Int(localPoolBalance.rounded())
                    viewModel.poolMode = localPoolMode
                    viewModel.isDualPool = localPoolMode == 1

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
            localPrimaryStratumURL = viewModel.stratumURL
            localPrimaryStratumPortString = viewModel.stratumPortString
            localPrimaryStratumUser = viewModel.stratumUser
            localSecondaryStratumURL = viewModel.fallbackStratumURL
            localSecondaryStratumPortString = viewModel.fallbackStratumPortString
            localSecondaryStratumUser = viewModel.fallbackStratumUser
            localPoolBalance = Double(viewModel.poolBalance)
            localPoolMode = viewModel.poolMode
            selectedPoolIndex = 0
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
            previewViewModel.fallbackStratumURL = "public-pool.io"
            previewViewModel.fallbackStratumPortString = "21496"
            previewViewModel.fallbackStratumUser = "testUser.worker2"
            previewViewModel.poolBalance = 60
            previewViewModel.poolMode = 1
            previewViewModel.isDualPool = true

            return NavigationView {
                PoolConfigurationView(viewModel: previewViewModel)
            }
        }
    }
#endif
