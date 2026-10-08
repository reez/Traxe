import SwiftUI
import UserNotifications

#if canImport(UIKit)
    import UIKit
#endif

struct MinerAlertsSection: View {
    let viewModel: MinerAlertsSettingsViewModel

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section {
            Toggle(
                "Miner Alerts",
                isOn: Binding(
                    get: { viewModel.toggleIsOn },
                    set: { newValue in
                        Task { await viewModel.setEnabled(newValue) }
                    }
                )
            )
            .tint(.accentColor)
            // Permission can still be pending, and enabling can be refused, so the
            // control stays put until the request it started has settled.
            .disabled(viewModel.isRequestInFlight)
            .task { await viewModel.refresh() }
            .onChange(of: scenePhase) { _, newPhase in
                // Permission can change while the user is in iOS Settings.
                guard newPhase == .active else { return }
                Task { await viewModel.refresh() }
            }

            if viewModel.showsNotificationAccessWarning {
                VStack(alignment: .leading, spacing: 12) {
                    Label {
                        Text(
                            "Notifications are turned off for Traxe in iOS Settings, so this miner can't send alerts."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }

                    Button("Open Notification Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else {
                            return
                        }
                        openURL(url)
                    }
                }
            }
        } header: {
            Text("Alerts")
        } footer: {
            Text(
                "Notifies you when this miner (\(viewModel.ipAddress)) goes offline or runs hot. Every miner has its own setting, so other miners are not affected. Add a Traxe widget to receive alerts. Checks run when widgets refresh and only while this device is on the same Wi-Fi network as your miners."
            )
        }
    }
}

#Preview("Miner Alerts - On") {
    Form {
        MinerAlertsSection(
            viewModel: previewMinerAlertsViewModel(
                suiteName: "preview.miner-alerts.on",
                isEnabled: true,
                authorizationStatus: .authorized
            )
        )
    }
}

#Preview("Miner Alerts - Notifications Blocked") {
    Form {
        MinerAlertsSection(
            viewModel: previewMinerAlertsViewModel(
                suiteName: "preview.miner-alerts.blocked",
                isEnabled: true,
                authorizationStatus: .denied
            )
        )
    }
}

@MainActor
private func previewMinerAlertsViewModel(
    suiteName: String,
    isEnabled: Bool,
    authorizationStatus: UNAuthorizationStatus
) -> MinerAlertsSettingsViewModel {
    let ipAddress = "192.168.1.100"
    let preferences = UserDefaults(suiteName: suiteName).map(MinerAlertPreferences.init(defaults:))
    preferences?.setEnabled(isEnabled, for: ipAddress)

    return MinerAlertsSettingsViewModel(
        ipAddress: ipAddress,
        preferences: preferences,
        authorization: MinerAlertNotificationAuthorization(
            currentStatus: { authorizationStatus },
            requestAuthorization: { authorizationStatus }
        ),
        reloadWidgetTimelines: {}
    )
}
