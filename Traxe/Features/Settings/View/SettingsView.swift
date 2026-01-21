import RevenueCat
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
    @State private var showingPaywallSheet = false
    @State private var customerInfo: CustomerInfo? = nil

    @Environment(\.dismiss) var dismiss
    @Environment(\.requestReview) var requestReview
    #if DEBUG
        @Environment(\.previewUpgradeState) private var previewUpgradeState
    #else
        private var previewUpgradeState: UpgradeState? { nil }
    #endif

    private var proIsActive: Bool {
        customerInfo?.entitlements["Pro"]?.isActive == true
    }

    private var miners5IsActive: Bool {
        customerInfo?.entitlements["Miners_5"]?.isActive == true
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
        return .upgrade
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
                                    .foregroundStyle(.secondary)
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
                .sheet(isPresented: $showingPaywallSheet) {
                    PaywallView()
                }
            }
        }
        .onAppear {
            viewModel.loadSettings()
        }
        .task {
            guard previewUpgradeState == nil, !ProcessInfo.isPreview else { return }
            for await info in Purchases.shared.customerInfoStream {
                customerInfo = info
            }
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

private enum UpgradeState {
    case loading
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
    fileprivate var previewUpgradeState: UpgradeState? {
        get { self[PreviewUpgradeStateKey.self] }
        set { self[PreviewUpgradeStateKey.self] = newValue }
    }
}
