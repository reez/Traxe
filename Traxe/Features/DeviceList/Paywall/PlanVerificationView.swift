import SwiftUI

@MainActor
struct PlanVerificationView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var subscriptionStatus: SubscriptionStatusViewModel
    let savedDeviceCount: Int
    let onVerified: () -> Void
    let onViewPlans: () -> Void
    @State private var restoreViewModel: RestorePurchasesViewModel
    @State private var retryAttempt = 0

    init(
        subscriptionStatus: SubscriptionStatusViewModel,
        savedDeviceCount: Int,
        onVerified: @escaping () -> Void,
        onViewPlans: @escaping () -> Void,
        restoreViewModel: RestorePurchasesViewModel? = nil
    ) {
        self.subscriptionStatus = subscriptionStatus
        self.savedDeviceCount = savedDeviceCount
        self.onVerified = onVerified
        self.onViewPlans = onViewPlans
        _restoreViewModel = State(initialValue: restoreViewModel ?? RestorePurchasesViewModel())
    }

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Plan Needs Verification", systemImage: "exclamationmark.icloud")
            } description: {
                Text(
                    "Traxe hasn’t verified your plan yet. Retry or restore purchases to check access to more miners. Your saved miners remain available."
                )
                if subscriptionStatus.refreshFailed && !subscriptionStatus.isRefreshing
                    && !restoreViewModel.isRestoring
                {
                    Text("Couldn’t verify your plan right now. Please try again shortly.")
                }
            } actions: {
                Button {
                    retryAttempt += 1
                } label: {
                    if subscriptionStatus.isRefreshing {
                        ProgressView("Checking plan…")
                    } else {
                        Text("Retry")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(subscriptionStatus.isRefreshing || restoreViewModel.isRestoring)

                RestorePurchasesButton(viewModel: restoreViewModel) {
                    Task { await subscriptionStatus.refreshAfterRestore() }
                }
                .disabled(subscriptionStatus.isRefreshing)

                Button("View Plans", action: onViewPlans)
                    .disabled(restoreViewModel.isRestoring)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .task(id: retryAttempt) {
                guard retryAttempt > 0 else { return }
                await subscriptionStatus.refresh()
            }
            .onChange(
                of: subscriptionStatus.addMinerDestination(savedDeviceCount: savedDeviceCount),
                initial: true
            ) { _, destination in
                if destination != .verifyPlan { onVerified() }
            }
        }
    }
}

#Preview {
    PlanVerificationView(
        subscriptionStatus: SubscriptionStatusViewModel(),
        savedDeviceCount: 1,
        onVerified: {},
        onViewPlans: {}
    )
}
