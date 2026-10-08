import RevenueCatUI
import SwiftUI

/// Keeps the SDK event wiring shared by the live paywall and callback integration tests.
struct PaywallEventModifier: ViewModifier {
    let outcome: PaywallOutcomeViewModel
    let dismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .onPurchaseStarted { _ in outcome.beginAction() }
            // RevenueCat's fallback paywall emits restore-start without restore-completed.
            // Do not make explicit dismissal depend on that completion callback.
            .onPurchaseCancelled { outcome.finishAction() }
            .onPurchaseFailure { _ in outcome.finishAction() }
            .onRestoreFailure { _ in outcome.finishAction() }
            .onWebCheckoutOpened { outcome.finishAction() }
            .onPurchaseCompleted { customerInfo in
                if outcome.completePurchase(
                    hasActivePlan: SubscriptionSnapshot(customerInfo).plan != .free
                ) {
                    dismiss()
                }
            }
            .onRestoreCompleted { customerInfo in
                if outcome.completeRestore(
                    hasActivePlan: SubscriptionSnapshot(customerInfo).plan != .free
                ) {
                    dismiss()
                }
            }
            .onRequestedDismissal {
                if outcome.permitsSDKDismissal { dismiss() }
            }
    }
}
