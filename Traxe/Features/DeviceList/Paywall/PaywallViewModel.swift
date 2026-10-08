import Observation
import RevenueCat

@MainActor
@Observable
final class PaywallViewModel {
    private(set) var currentOffering: Offering?
    private(set) var errorMessage: String?

    private let fetchOffering: () async throws -> Offering?

    init(
        fetchOffering: @escaping () async throws -> Offering? = {
            let offerings = try await Purchases.shared.offerings()
            return offerings["miners_5"] ?? offerings.current
        }
    ) {
        self.fetchOffering = fetchOffering
    }

    func loadOffering() async {
        errorMessage = nil
        do {
            let offering = try await fetchOffering()
            try Task.checkCancellation()
            currentOffering = offering
            if offering == nil {
                errorMessage = "Plans aren’t available right now. Please try again."
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Couldn’t load plans. Please try again."
        }
    }
}
