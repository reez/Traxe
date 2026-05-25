import Observation
import SwiftData
import SwiftUI

struct PoolConfigurationView: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedPoolIndex: Int = 0
    @State private var localPrimaryStratumURL: String = ""
    @State private var localPrimaryStratumPortString: String = ""
    @State private var localPrimaryStratumUser: String = ""
    @State private var localSecondaryStratumURL: String = ""
    @State private var localSecondaryStratumPortString: String = ""
    @State private var localSecondaryStratumUser: String = ""
    @State private var localPrimaryStratumProtocol: String = "SV1"
    @State private var localSecondaryStratumProtocol: String = "SV1"
    @State private var localPrimaryStratumV2ChannelType: String = "standard"
    @State private var localSecondaryStratumV2ChannelType: String = "standard"
    @State private var localPrimaryStratumV2AuthorityPubkey: String = ""
    @State private var localSecondaryStratumV2AuthorityPubkey: String = ""
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

    private var activeStratumProtocol: Binding<String> {
        selectedPoolIndex == 0 ? $localPrimaryStratumProtocol : $localSecondaryStratumProtocol
    }

    private var activeStratumV2ChannelType: Binding<String> {
        selectedPoolIndex == 0
            ? $localPrimaryStratumV2ChannelType
            : $localSecondaryStratumV2ChannelType
    }

    private var activeStratumV2AuthorityPubkey: Binding<String> {
        selectedPoolIndex == 0
            ? $localPrimaryStratumV2AuthorityPubkey
            : $localSecondaryStratumV2AuthorityPubkey
    }

    var body: some View {
        Form {
            Section("Pool Configuration") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pool Mode".uppercased())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Pool Mode", selection: $localPoolMode) {
                        Text("Failover").tag(0)
                        Text("Dual Pool").tag(1)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    Text("Changing pool mode may require a device restart.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                if localIsDualPool {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(poolBalanceTitle.uppercased())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Slider(value: $localPoolBalance, in: 1...99, step: 1)
                        Text(
                            "Distributes jobs between the primary and secondary pool, e.g., 70/30."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if Int(localPoolBalance.rounded()) == 1
                            || Int(localPoolBalance.rounded()) == 99
                        {
                            Text(
                                "Very low ratios can make pool hashrate estimates inaccurate."
                            )
                            .font(.caption)
                            .italic()
                            .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                    TextField("NA.lincoin.com", text: activeStratumURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                    Text("Do not include 'stratum+tcp://' or port.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stratum Port".uppercased())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("3333", text: activeStratumPortString)
                        .keyboardType(.numberPad)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stratum User".uppercased())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    MonospacedIdentifierEditor(
                        placeholder: "pod256.traxe",
                        text: activeStratumUser
                    )
                }

                if viewModel.supportsStratumProtocolSettings {
                    StratumProtocolDetailsView(
                        poolTitle: poolSegmentTitles[selectedPoolIndex],
                        protocolValue: activeStratumProtocol,
                        channelType: activeStratumV2ChannelType,
                        authorityPubkey: activeStratumV2AuthorityPubkey
                    )
                    .padding(.vertical, 4)
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
                    viewModel.stratumProtocol = localPrimaryStratumProtocol
                    viewModel.fallbackStratumProtocol = localSecondaryStratumProtocol
                    viewModel.stratumV2ChannelType = localPrimaryStratumV2ChannelType
                    viewModel.fallbackStratumV2ChannelType = localSecondaryStratumV2ChannelType
                    viewModel.stratumV2AuthorityPubkey = localPrimaryStratumV2AuthorityPubkey
                    viewModel.fallbackStratumV2AuthorityPubkey =
                        localSecondaryStratumV2AuthorityPubkey
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
            localPrimaryStratumProtocol = Self.protocolValueForControl(viewModel.stratumProtocol)
            localSecondaryStratumProtocol = Self.protocolValueForControl(
                viewModel.fallbackStratumProtocol
            )
            localPrimaryStratumV2ChannelType = Self.channelTypeForControl(
                viewModel.stratumV2ChannelType
            )
            localSecondaryStratumV2ChannelType = Self.channelTypeForControl(
                viewModel.fallbackStratumV2ChannelType
            )
            localPrimaryStratumV2AuthorityPubkey = viewModel.stratumV2AuthorityPubkey
            localSecondaryStratumV2AuthorityPubkey = viewModel.fallbackStratumV2AuthorityPubkey
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

    private static func protocolValueForControl(_ value: String) -> String {
        StratumProtocolSettingsValidator.protocolValueToSave(value) ?? "SV1"
    }

    private static func channelTypeForControl(_ value: String) -> String {
        StratumProtocolSettingsValidator.channelTypeToSave(value) ?? "standard"
    }
}

#if DEBUG
    struct PoolConfigurationView_Previews: PreviewProvider {
        static var previews: some View {
            Group {
                NavigationStack {
                    PoolConfigurationView(viewModel: publicPoolSV2PreviewViewModel())
                }
                .previewDisplayName("Public Pool SV2")

                NavigationStack {
                    PoolConfigurationView(viewModel: dualPoolPreviewViewModel())
                }
                .previewDisplayName("Dual Pool")
            }
        }

        private static func publicPoolSV2PreviewViewModel() -> SettingsViewModel {
            let previewViewModel = SettingsViewModel(
                sharedUserDefaults: previewSharedDefaults(named: "PublicPoolSV2"),
                modelContext: previewContainer().mainContext,
                shouldFetchDeviceSettingsOnLoad: false
            )
            previewViewModel.stratumURL = "public-pool.io"
            previewViewModel.stratumPortString = "3333"
            previewViewModel.stratumUser = "bc1qpublicpoolpreview.worker1"
            previewViewModel.fallbackStratumURL = ""
            previewViewModel.fallbackStratumPortString = ""
            previewViewModel.fallbackStratumUser = ""
            previewViewModel.supportsStratumProtocolSettings = true
            previewViewModel.stratumProtocol = "SV2"
            previewViewModel.fallbackStratumProtocol = "SV1"
            previewViewModel.stratumV2ChannelType = "extended"
            previewViewModel.fallbackStratumV2ChannelType = "standard"
            previewViewModel.stratumV2AuthorityPubkey =
                "9c4zpyJ2ndm4e8sP2uNc1VNCGxYjqaxWS6wUCjk8zFj6njFquH6"
            previewViewModel.fallbackStratumV2AuthorityPubkey = ""
            previewViewModel.poolBalance = 50
            previewViewModel.poolMode = 0
            previewViewModel.isDualPool = false
            return previewViewModel
        }

        private static func dualPoolPreviewViewModel() -> SettingsViewModel {
            let previewViewModel = SettingsViewModel(
                sharedUserDefaults: previewSharedDefaults(named: "DualPool"),
                modelContext: previewContainer().mainContext,
                shouldFetchDeviceSettingsOnLoad: false
            )
            previewViewModel.stratumURL = "stratum.slushpool.com"
            previewViewModel.stratumPortString = "3333"
            previewViewModel.stratumUser = "testUser.worker1"
            previewViewModel.fallbackStratumURL = "public-pool.io"
            previewViewModel.fallbackStratumPortString = "21496"
            previewViewModel.fallbackStratumUser = "testUser.worker2"
            previewViewModel.supportsStratumProtocolSettings = true
            previewViewModel.stratumProtocol = "SV2"
            previewViewModel.fallbackStratumProtocol = "SV1"
            previewViewModel.stratumV2ChannelType = "extended"
            previewViewModel.stratumV2AuthorityPubkey =
                "9c4zpyJ2ndm4e8sP2uNc1VNCGxYjqaxWS6wUCjk8zFj6njFquH6"
            previewViewModel.poolBalance = 60
            previewViewModel.poolMode = 1
            previewViewModel.isDualPool = true
            return previewViewModel
        }

        private static func previewContainer() -> ModelContainer {
            let previewContainer: ModelContainer = {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                do {
                    return try ModelContainer(for: HistoricalDataPoint.self, configurations: config)
                } catch {
                    fatalError("Failed to create preview container: \\(error)")
                }
            }()
            return previewContainer
        }

        private static func previewSharedDefaults(named name: String) -> UserDefaults? {
            let suiteName = "traxe.poolConfigurationPreview.\(name)"
            let previewSharedDefaults = UserDefaults(suiteName: suiteName)
            previewSharedDefaults?.removePersistentDomain(
                forName: suiteName
            )
            previewSharedDefaults?.set("192.168.1.100", forKey: "bitaxeIPAddress")
            return previewSharedDefaults
        }
    }
#endif
