import Foundation
import RevenueCat

struct SubscriptionSnapshot: Hashable, Sendable {
    enum Plan: Int, Hashable, Sendable {
        case free
        case miners5
        case pro

        var deviceLimit: Int {
            switch self {
            case .free: 1
            case .miners5: 5
            case .pro: Int.max
            }
        }
    }

    let plan: Plan
    let requestDate: Date
    let isComputedOffline: Bool

    init(plan: Plan, requestDate: Date, isComputedOffline: Bool = false) {
        self.plan = plan
        self.requestDate = requestDate
        self.isComputedOffline = isComputedOffline
    }

    init(_ info: CustomerInfo) {
        plan =
            info.entitlements["Pro"]?.isActive == true
            ? .pro : info.entitlements["Miners_5"]?.isActive == true ? .miners5 : .free
        requestDate = info.requestDate
        isComputedOffline = info.entitlements.verification == .verifiedOnDevice
    }
}
