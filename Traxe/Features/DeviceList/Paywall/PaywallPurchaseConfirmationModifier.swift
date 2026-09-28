import SwiftUI

struct PaywallPurchaseConfirmationModifier: ViewModifier {
    let subscriptionStatus: SubscriptionStatusViewModel
    @Bindable var confirmation: PaywallPurchaseConfirmation
    let onCancelled: () -> Void

    func body(content: Content) -> some View {
        content
            // The SDK fallback and web checkout buttons bypass onPurchaseInitiated.
            // Gate the whole paywall until the warning is acknowledged instead.
            .disabled(!confirmation.permitsPurchases)
            .alert("Check Your Existing Plan", isPresented: $confirmation.isPresented) {
                Button("Continue to Plans") { confirmation.resolve(shouldProceed: true) }
                Button("Cancel", role: .cancel) { confirmation.resolve(shouldProceed: false) }
            } message: {
                Text(confirmation.message)
            }
            .onAppear {
                confirmation.activate()
                confirmation.request(
                    plan: subscriptionStatus.plan,
                    hasCurrentResponse: subscriptionStatus.hasCurrentResponse
                        && !subscriptionStatus.refreshFailed,
                    resume: { if !$0 { onCancelled() } }
                )
            }
            .onDisappear { confirmation.deactivate() }
    }
}
