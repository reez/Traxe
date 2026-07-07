import Foundation
import UserNotifications

/// Injection seam for the app-global iOS notification authorization that miner alerts
/// depend on, so the Settings alert logic stays testable without a real permission prompt.
struct MinerAlertNotificationAuthorization: Sendable {
    var currentStatus: @Sendable () async -> UNAuthorizationStatus
    var requestAuthorization: @Sendable () async -> UNAuthorizationStatus

    static let live = MinerAlertNotificationAuthorization(
        currentStatus: {
            await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        },
        requestAuthorization: {
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            return await center.notificationSettings().authorizationStatus
        }
    )
}
