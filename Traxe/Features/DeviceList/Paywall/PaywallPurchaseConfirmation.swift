import Observation

@MainActor
@Observable
final class PaywallPurchaseConfirmation {
    var isPresented = false
    private(set) var message = ""
    private(set) var permitsPurchases = false
    private var isActive = false
    private var resumePurchase: ((Bool) -> Void)?

    func activate() {
        isActive = true
        permitsPurchases = false
    }

    func request(
        plan: SubscriptionSnapshot.Plan,
        hasCurrentResponse: Bool,
        resume: @escaping (Bool) -> Void
    ) {
        guard isActive, resumePurchase == nil else {
            resume(false)
            return
        }
        guard plan != .free || !hasCurrentResponse else {
            permitsPurchases = true
            resume(true)
            return
        }
        message = !hasCurrentResponse
            ? "Traxe hasn’t verified your existing purchases. If you already subscribe, buying another plan may add a separate charge and won’t cancel your subscription. Cancel and try Restore Purchases first if you’re unsure."
            : "You already have an active Traxe plan. Buying another plan may add a separate charge and won’t cancel an existing subscription. Continue only if you want to browse additional plans."
        resumePurchase = resume
        isPresented = true
    }

    func resolve(shouldProceed: Bool) {
        let resume = resumePurchase
        guard resume != nil else { return }
        resumePurchase = nil
        isPresented = false
        permitsPurchases = shouldProceed
        resume?(shouldProceed)
    }

    func deactivate() {
        isActive = false
        resolve(shouldProceed: false)
        permitsPurchases = false
    }
}
