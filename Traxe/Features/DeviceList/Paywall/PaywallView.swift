import RevenueCat
import RevenueCatUI
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) var dismiss
    @State var currentOffering: Offering?

    var body: some View {
        if let offering = currentOffering {
            RevenueCatUI.PaywallView(offering: offering)
                .onPurchaseCompleted { customerInfo in
                    handlePurchaseOrRestore(customerInfo: customerInfo)
                }
                .onRestoreCompleted { customerInfo in
                    handlePurchaseOrRestore(customerInfo: customerInfo)
                }
        } else {
            ProgressView()
                .onAppear {
                    fetchOffering()
                }
        }
    }

    private func fetchOffering() {
        Task {
            do {
                let offerings = try await Purchases.shared.offerings()
                if let specificOffering = offerings["miners_5"] {
                    currentOffering = specificOffering
                } else {
                    currentOffering = offerings.current
                }

                if let finalOffering = currentOffering {
                } else {
                }

            } catch {
            }
        }
    }

    private func handlePurchaseOrRestore(customerInfo: CustomerInfo) {
        let proIsActive = customerInfo.entitlements["Pro"]?.isActive == true
        let miners5IsActive = customerInfo.entitlements["Miners_5"]?.isActive == true
        if proIsActive || miners5IsActive {
        } else {
        }
        dismiss()
    }
}

#Preview {
    PaywallView()
}
