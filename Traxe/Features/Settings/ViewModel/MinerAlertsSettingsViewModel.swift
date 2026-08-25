import Foundation
import Observation
import UserNotifications
import WidgetKit

/// Drives the Alerts section of Settings for the one miner the screen was opened for.
///
/// The opt-in is stored per miner in the app group, while iOS notification permission is
/// app-global: enabling alerts asks for permission only when it has never been requested,
/// and a blocked permission is surfaced instead of leaving the toggle looking enabled.
///
/// Enabling can suspend while permission is read or requested, so every request carries a
/// version. Only the newest request may store a preference or settle the toggle, which
/// keeps the last thing the user asked for as the one that wins.
@Observable
@MainActor
final class MinerAlertsSettingsViewModel {
    let ipAddress: String
    private(set) var isEnabled: Bool = false
    private(set) var isNotificationAccessBlocked: Bool = false
    private(set) var isRequestInFlight: Bool = false

    /// What the toggle shows: the requested value while a request is in flight, otherwise
    /// the stored preference. A refused request therefore falls back to the stored value.
    var toggleIsOn: Bool {
        requestedValue ?? isEnabled
    }

    /// Only worth showing once the user has asked for alerts on this miner; an untouched
    /// toggle should not nag about a permission the app never needed.
    var showsNotificationAccessWarning: Bool {
        isNotificationAccessBlocked && (isEnabled || didAttemptEnable)
    }

    private var didAttemptEnable = false
    private var requestedValue: Bool?
    private var latestRequestID = 0
    private let preferences: MinerAlertPreferences?
    private let authorization: MinerAlertNotificationAuthorization
    private let reloadWidgetTimelines: () -> Void

    init(
        ipAddress: String,
        preferences: MinerAlertPreferences? = MinerAlertPreferences.appGroup(),
        authorization: MinerAlertNotificationAuthorization = .live,
        reloadWidgetTimelines: @escaping () -> Void = {
            WidgetCenter.shared.reloadTimelines(ofKind: "TraxeWidget")
        }
    ) {
        self.ipAddress = ipAddress
        self.preferences = preferences
        self.authorization = authorization
        self.reloadWidgetTimelines = reloadWidgetTimelines
        isEnabled = preferences?.isEnabled(for: ipAddress) ?? false
    }

    func refresh() async {
        let requestID = latestRequestID
        let status = await authorization.currentStatus()
        // A toggle started while permission was being read owns the state from here on.
        guard requestID == latestRequestID else { return }
        isEnabled = preferences?.isEnabled(for: ipAddress) ?? false
        isNotificationAccessBlocked = Self.isBlocked(status)
    }

    func setEnabled(_ newValue: Bool) async {
        latestRequestID += 1
        let requestID = latestRequestID
        requestedValue = newValue
        isRequestInFlight = true
        defer { settle(requestID) }

        guard newValue else {
            didAttemptEnable = false
            store(false)
            return
        }

        didAttemptEnable = true
        var status = await authorization.currentStatus()
        if status == .notDetermined {
            status = await authorization.requestAuthorization()
        }

        // The user changed the toggle again while permission was pending, so this
        // request is stale and must not write a preference or move the toggle.
        guard requestID == latestRequestID else { return }
        isNotificationAccessBlocked = Self.isBlocked(status)
        store(status == .authorized)
    }

    private func settle(_ requestID: Int) {
        guard requestID == latestRequestID else { return }
        requestedValue = nil
        isRequestInFlight = false
    }

    private func store(_ newValue: Bool) {
        // Reading the preference back keeps the toggle honest when there is nothing to
        // write to, such as a missing app group or an empty miner selection.
        guard let preferences else { return }
        preferences.setEnabled(newValue, for: ipAddress)
        isEnabled = preferences.isEnabled(for: ipAddress)
        reloadWidgetTimelines()
    }

    /// The widget only posts notifications for `.authorized`, so anything else — other
    /// than a permission that was never requested — cannot deliver miner alerts.
    private static func isBlocked(_ status: UNAuthorizationStatus) -> Bool {
        status != .authorized && status != .notDetermined
    }
}
