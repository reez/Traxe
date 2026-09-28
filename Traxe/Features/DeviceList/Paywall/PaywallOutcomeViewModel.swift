import Observation
import RevenueCat

@MainActor
@Observable
final class PaywallOutcomeViewModel {
    private(set) var purchaseNeedsRecovery = false
    private(set) var isActionInProgress = false
    var showingRestoreMessage = false
    private(set) var recoveryMessage =
        "Your purchase completed, but Traxe hasn’t received access to your plan yet. You don’t need to buy it again. Try verifying the purchase, restore purchases, or contact support."
    private let syncPurchase: () async throws -> Bool

    init(
        syncPurchase: @escaping () async throws -> Bool = {
            let info = try await Purchases.shared.syncPurchases()
            return SubscriptionSnapshot(info).plan != .free
        }
    ) {
        self.syncPurchase = syncPurchase
    }

    var permitsSDKDismissal: Bool {
        !purchaseNeedsRecovery && !showingRestoreMessage && !isActionInProgress
    }

    func beginAction() {
        isActionInProgress = true
    }

    func finishAction() {
        isActionInProgress = false
    }

    func completePurchase(hasActivePlan: Bool) -> Bool {
        isActionInProgress = false
        purchaseNeedsRecovery = !hasActivePlan
        return hasActivePlan
    }

    func completeRestore(hasActivePlan: Bool) -> Bool {
        isActionInProgress = false
        showingRestoreMessage = !hasActivePlan
        if hasActivePlan { purchaseNeedsRecovery = false }
        return hasActivePlan
    }

    func retryActivation() async -> Bool {
        guard !isActionInProgress else { return false }
        isActionInProgress = true
        defer { isActionInProgress = false }
        do {
            let hasActivePlan = try await syncPurchase()
            try Task.checkCancellation()
            purchaseNeedsRecovery = !hasActivePlan
            if !hasActivePlan {
                recoveryMessage =
                    "Your purchase still hasn’t activated a Traxe plan. You don’t need to buy it again. Restore purchases or contact support so we can help."
            }
            return hasActivePlan
        } catch {
            guard !Task.isCancelled else { return false }
            recoveryMessage =
                "Couldn’t verify your purchase. Check your connection and try again. You don’t need to buy it again."
            return false
        }
    }
}
