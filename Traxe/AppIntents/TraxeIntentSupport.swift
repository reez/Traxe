import Foundation
import RevenueCat

struct TraxeIntentSupport {
    private static let appGroupSuiteName = "group.matthewramsden.traxe"
    private static let savedDevicesKey = "savedDevices"

    static func loadSavedDevices() -> [SavedDevice] {
        guard
            let defaults = UserDefaults(suiteName: appGroupSuiteName),
            let data = defaults.data(forKey: savedDevicesKey)
        else {
            return []
        }

        do {
            return try JSONDecoder().decode([SavedDevice].self, from: data)
        } catch {
            return []
        }
    }

    static func resolveSubscriptionAccessPolicy() async -> SubscriptionAccessPolicy {
        guard Purchases.isConfigured else {
            return .accommodatingFallback
        }

        do {
            let customerInfo = try await Purchases.shared.customerInfo(fetchPolicy: .fromCacheOnly)
            let proIsActive = customerInfo.entitlements["Pro"]?.isActive == true
            let miners5IsActive = customerInfo.entitlements["Miners_5"]?.isActive == true

            return SubscriptionAccessPolicy(
                proIsActive: proIsActive,
                miners5IsActive: miners5IsActive,
                hasLoadedSubscription: true
            )
        } catch {
            return .accommodatingFallback
        }
    }

    static func formattedUptime(from uptime: TimeInterval) -> String {
        guard uptime > 0 else { return "unknown uptime" }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: uptime) ?? "unknown uptime"
    }
}
