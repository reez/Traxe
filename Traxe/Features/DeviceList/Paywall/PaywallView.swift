import RevenueCat
import RevenueCatUI
import SwiftUI

@MainActor
struct PaywallView: View {
    @Environment(\.dismiss) var dismiss
    @State private var viewModel: PaywallViewModel
    private let makePaywall: @MainActor (Offering) -> RevenueCatUI.PaywallView
    @State private var restoreViewModel = RestorePurchasesViewModel()
    @State private var loadAttempt = 0
    @State private var outcome = PaywallOutcomeViewModel()
    @State private var subscriptionStatus: SubscriptionStatusViewModel
    private let observesSubscriptionStatus: Bool
    @State private var purchaseConfirmation: PaywallPurchaseConfirmation

    init(
        fetchOffering: (() async throws -> Offering?)? = nil,
        purchaseConfirmation: PaywallPurchaseConfirmation? = nil,
        subscriptionStatus: SubscriptionStatusViewModel? = nil,
        makePaywall: @escaping @MainActor (Offering) -> RevenueCatUI.PaywallView = {
            RevenueCatUI.PaywallView(offering: $0)
        }
    ) {
        _viewModel = State(
            initialValue: fetchOffering.map { PaywallViewModel(fetchOffering: $0) }
                ?? PaywallViewModel()
        )
        self.makePaywall = makePaywall
        _purchaseConfirmation = State(initialValue: purchaseConfirmation ?? PaywallPurchaseConfirmation())
        _subscriptionStatus = State(initialValue: subscriptionStatus ?? SubscriptionStatusViewModel())
        observesSubscriptionStatus = subscriptionStatus == nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if outcome.purchaseNeedsRecovery {
                    PaywallPurchaseRecoveryView(
                        outcome: outcome,
                        restoreViewModel: restoreViewModel,
                        onRecovered: { dismiss() }
                    )
                } else if let offering = viewModel.currentOffering {
                    makePaywall(offering)
                        .modifier(PaywallEventModifier(outcome: outcome, dismiss: { dismiss() }))
                        .modifier(
                            PaywallPurchaseConfirmationModifier(
                                subscriptionStatus: subscriptionStatus,
                                confirmation: purchaseConfirmation,
                                onCancelled: { dismiss() }
                            )
                        )
                } else if let errorMessage = viewModel.errorMessage {
                    ContentUnavailableView {
                        Label("Plans Unavailable", systemImage: "exclamationmark.icloud")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Retry") {
                            loadAttempt += 1
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(restoreViewModel.isRestoring)
                    }
                } else {
                    ProgressView("Loading plans…")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                    .disabled(outcome.isActionInProgress || restoreViewModel.isRestoring)
                }
                if viewModel.currentOffering == nil, viewModel.errorMessage != nil {
                    ToolbarItem(placement: .bottomBar) {
                        RestorePurchasesButton(
                            viewModel: restoreViewModel,
                            onRestored: { dismiss() }
                        )
                    }
                }
            }
            .alert("No Active Plan Found", isPresented: $outcome.showingRestoreMessage) {
                Button("OK") {}
            } message: {
                Text("No active Traxe plan was found for this Apple Account.")
            }
            .interactiveDismissDisabled(outcome.isActionInProgress || restoreViewModel.isRestoring)
            .task(id: loadAttempt) {
                await viewModel.loadOffering()
            }
            .task {
                guard observesSubscriptionStatus, Purchases.isConfigured, !ProcessInfo.isPreview else {
                    return
                }
                await subscriptionStatus.observe()
            }
        }
    }
}

#Preview {
    PaywallView()
}
