import Foundation

struct SubscriptionAccessPolicy {
    let proIsActive: Bool
    let miners5IsActive: Bool
    let hasLoadedSubscription: Bool

    init(
        proIsActive: Bool,
        miners5IsActive: Bool,
        hasLoadedSubscription: Bool
    ) {
        self.proIsActive = proIsActive
        self.miners5IsActive = miners5IsActive
        self.hasLoadedSubscription = hasLoadedSubscription
    }

    static let accommodatingFallback = SubscriptionAccessPolicy(
        proIsActive: false,
        miners5IsActive: false,
        hasLoadedSubscription: false
    )

    var deviceLimit: Int {
        guard hasLoadedSubscription else {
            return Int.max
        }
        if proIsActive {
            return Int.max
        }
        if miners5IsActive {
            return 5
        }
        return 1
    }

    var shouldShowLocks: Bool {
        hasLoadedSubscription
    }

    var shouldShowSubscriptionExpiredAlert: Bool {
        hasLoadedSubscription && !proIsActive && !miners5IsActive
    }

    func isDeviceAccessible(at index: Int) -> Bool {
        index < deviceLimit
    }

    func accessibleDevices(from devices: [SavedDevice]) -> [SavedDevice] {
        guard deviceLimit != Int.max else {
            return devices
        }
        return Array(devices.prefix(deviceLimit))
    }
}
