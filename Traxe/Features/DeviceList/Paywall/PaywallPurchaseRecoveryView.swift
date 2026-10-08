import SwiftUI

struct PaywallPurchaseRecoveryView: View {
    @Bindable var outcome: PaywallOutcomeViewModel
    @Bindable var restoreViewModel: RestorePurchasesViewModel
    var onRecovered: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Purchase Needs Verification", systemImage: "checkmark.icloud")
        } description: {
            Text(outcome.recoveryMessage)
        } actions: {
            Button {
                Task {
                    if await outcome.retryActivation() { onRecovered() }
                }
            } label: {
                if outcome.isActionInProgress {
                    ProgressView("Verifying purchase…")
                } else {
                    Text("Verify Purchase")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(outcome.isActionInProgress || restoreViewModel.isRestoring)

            RestorePurchasesButton(viewModel: restoreViewModel, onRestored: onRecovered)
                .disabled(outcome.isActionInProgress)

            if let supportURL = URL(
                string: "mailto:ramsden.matthew@gmail.com?subject=Traxe%20Purchase%20Support"
            ) {
                Link("Contact Support", destination: supportURL)
            }
        }
    }
}
