import Foundation
import UserNotifications

final class MinerAlertNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let identifier = notification.request.identifier
        // MinerAlertEvaluator uses these identifiers for offline and temperature alerts.
        guard identifier.hasPrefix("offline-") || identifier.hasPrefix("hot-") else {
            return []
        }
        return [.banner, .list, .sound]
    }
}
