import Observation
import RevenueCat

@MainActor
@Observable
final class RestorePurchasesViewModel {
    private(set) var isRestoring = false
    private(set) var message = ""
    private let restorePurchases: () async throws -> Bool

    init(
        restorePurchases: @escaping () async throws -> Bool = {
            let info = try await Purchases.shared.restorePurchases()
            return info.entitlements["Pro"]?.isActive == true
                || info.entitlements["Miners_5"]?.isActive == true
        }
    ) {
        self.restorePurchases = restorePurchases
    }

    func restore() async -> Bool {
        guard !isRestoring else { return false }
        isRestoring = true
        defer { isRestoring = false }
        do {
            let hasActivePlan = try await restorePurchases()
            message =
                hasActivePlan
                ? "Your Traxe plan has been restored."
                : "No active Traxe plan was found for this Apple Account."
            return hasActivePlan
        } catch {
            message = "Couldn’t restore purchases right now. Please try again shortly."
            return false
        }
    }
}
