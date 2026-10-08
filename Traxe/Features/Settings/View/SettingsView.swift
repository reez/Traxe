import Observation
import RevenueCat
import StoreKit
import SwiftData
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var showingRestartConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var showingDeleteFailure = false
    @State private var isAIEnabled = UserDefaults.standard.bool(forKey: "ai_enabled")
    @State private var alertsViewModel: MinerAlertsSettingsViewModel
    @State private var showingPaywallSheet = false
    @State private var subscriptionStatus = SubscriptionStatusViewModel()
    @State private var restoreViewModel = RestorePurchasesViewModel()
    private let onMinerDeleted: (String) -> Void

    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) var requestReview
    #if DEBUG
        @Environment(\.previewUpgradeState) private var previewUpgradeState
    #else
        private var previewUpgradeState: UpgradeState? { nil }
    #endif

    private var proIsActive: Bool {
        subscriptionStatus.plan == .pro
    }

    private var miners5IsActive: Bool {
        subscriptionStatus.plan == .miners5
    }

    private var upgradeState: UpgradeState {
        if let previewUpgradeState {
            return previewUpgradeState
        }
        if proIsActive {
            return .activePlan("Traxe Pro (Monthly)")
        }
        if miners5IsActive {
            return .activePlan("Traxe Pro (One-Time, 5 Miners)")
        }
        guard subscriptionStatus.hasCurrentResponse else {
            return subscriptionStatus.refreshFailed ? .unavailable : .loading
        }
        return .upgrade
    }

    init(
        viewModel: SettingsViewModel,
        onMinerDeleted: @escaping (String) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.onMinerDeleted = onMinerDeleted
        // Alerts belong to the miner this screen was opened for, so the selection is
        // captured here instead of following later edits to the connection field.
        _alertsViewModel = State(
            initialValue: MinerAlertsSettingsViewModel(ipAddress: viewModel.bitaxeIPAddress)
        )
    }

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

            NavigationStack {
                Form {

                    Section {
                        NavigationLink("Advanced Settings") {
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
                                    .foregroundStyle(.secondary)
                                    .animation(nil, value: viewModel.currentVersion)
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }

                    DangerZoneSection(
                        onRestart: { showingRestartConfirmation = true },
                        onDelete: { showingDeleteConfirmation = true },
                        canDeleteMiner: viewModel.canDeleteCurrentMiner
                    )

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

                    if !alertsViewModel.ipAddress.isEmpty {
                        MinerAlertsSection(viewModel: alertsViewModel)
                    }

                    switch upgradeState {
                    case .activePlan(let planName):
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(planName)
                                    .font(.headline)
                                Text("Thanks for supporting Traxe!")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .listRowInsets(
                                EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
                            )
                        } header: {
                            Text("Plan")
                        }
                    case .upgrade:
                        Section {
                            VStack(alignment: .leading, spacing: 12) {
                                Button {
                                    showingPaywallSheet = true
                                } label: {
                                    Text("View Plans")
                                        .foregroundStyle(.primary)
                                }
                                .disabled(restoreViewModel.isRestoring)

                                Text("Want to support Traxe or unlock more miners?")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .listRowInsets(
                                EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
                            )
                        } header: {
                            Text("Plan")
                        }
                    case .unavailable:
                        Section {
                            Text("Plan status unavailable")
                            Text(
                                "Your saved miners remain available. Try again to verify your plan."
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            Button("Retry") {
                                Task { await subscriptionStatus.refresh() }
                            }
                            .disabled(
                                subscriptionStatus.isRefreshing || restoreViewModel.isRestoring
                            )
                            Button("View Plans") {
                                showingPaywallSheet = true
                            }
                            .foregroundStyle(.primary)
                            .disabled(restoreViewModel.isRestoring)
                        } header: {
                            Text("Plan")
                        }
                        .id("unavailable-plan")
                    case .loading:
                        Section {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Checking plan status…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .listRowInsets(
                                EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
                            )
                        } header: {
                            Text("Plan")
                        }
                    }

                    Section {
                        RestorePurchasesButton(viewModel: restoreViewModel)
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
                    // Done confirms the sheet, so the semantic placement lets the system
                    // position it for the current bar layout rather than a fixed edge.
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            viewModel.saveSettings()
                            dismiss()
                        }
                    }
                }
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
                .alert("Delete Miner", isPresented: $showingDeleteConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        if let deletedIPAddress = viewModel.deleteCurrentMiner() {
                            dismiss()
                            onMinerDeleted(deletedIPAddress)
                        } else {
                            showingDeleteFailure = true
                        }
                    }
                } message: {
                    Text(
                        "This removes the miner from Traxe. The miner hardware and pool settings are not changed."
                    )
                }
                .alert("Couldn’t Delete Miner", isPresented: $showingDeleteFailure) {
                    Button("OK") {}
                } message: {
                    Text(viewModel.deleteMinerErrorMessage ?? "Traxe could not delete this miner.")
                }
                .sheet(isPresented: $showingPaywallSheet) {
                    PaywallView(subscriptionStatus: subscriptionStatus)
                }
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, previewUpgradeState == nil,
                !ProcessInfo.isPreview, Purchases.isConfigured
            else { return }
            await subscriptionStatus.observe()
        }
    }
}

#Preview("Settings - Pro Monthly") {
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
        .environment(\.previewUpgradeState, .activePlan("Traxe Pro (Monthly)"))
        .modelContainer(previewContainer)
}

#Preview("Settings - Pro One-Time") {
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
        .environment(\.previewUpgradeState, .activePlan("Traxe Pro (One-Time, 5 Miners)"))
        .modelContainer(previewContainer)
}

#Preview("Settings - Upgrade") {
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
        .environment(\.previewUpgradeState, .upgrade)
        .modelContainer(previewContainer)
}

enum UpgradeState {
    case loading
    case unavailable
    case upgrade
    case activePlan(String)
}

extension SettingsView {
    fileprivate var supportEmailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "ramsden.matthew@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Traxe - Support")
        ]
        return components.url
    }
}

private struct PreviewUpgradeStateKey: EnvironmentKey {
    static let defaultValue: UpgradeState? = nil
}

extension EnvironmentValues {
    var previewUpgradeState: UpgradeState? {
        get { self[PreviewUpgradeStateKey.self] }
        set { self[PreviewUpgradeStateKey.self] = newValue }
    }
}
