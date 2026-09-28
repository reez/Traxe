struct PlanVerificationPresentation {
    enum Completion: Equatable {
        case verified
        case viewPlans
    }

    var isPresented = false
    var showingAddMiner = false
    var showingPlans = false
    private var completion: Completion?

    mutating func present() {
        completion = nil
        isPresented = true
    }

    mutating func complete(_ completion: Completion) {
        guard isPresented else { return }
        self.completion = completion
        isPresented = false
    }

    mutating func didDismiss() -> Completion? {
        defer { completion = nil }
        return completion
    }

    mutating func presentAddMiner(destination: SubscriptionStatusViewModel.AddMinerDestination) {
        switch destination {
        case .addMiner: showingAddMiner = true
        case .verifyPlan: present()
        case .viewPlans: showingPlans = true
        }
    }

    mutating func routeAfterDismissal(
        destination: SubscriptionStatusViewModel.AddMinerDestination
    ) {
        switch didDismiss() {
        case .verified: presentAddMiner(destination: destination)
        case .viewPlans: showingPlans = true
        case nil: break
        }
    }
}
