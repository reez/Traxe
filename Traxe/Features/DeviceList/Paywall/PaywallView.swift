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
                currentOffering = try await Purchases.shared.offerings().current
            } catch {
            }
        }
    }

    private func handlePurchaseOrRestore(customerInfo: CustomerInfo) {
        if customerInfo.entitlements["pro_access"]?.isActive == true {
        } else {
        }
        dismiss()
    }
}

#Preview {
    PaywallView()
}
