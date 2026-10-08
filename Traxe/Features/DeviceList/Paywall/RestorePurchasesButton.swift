import SwiftUI

struct RestorePurchasesButton: View {
    @Bindable var viewModel: RestorePurchasesViewModel
    @State private var showingResult = false
    var onRestored: (() -> Void)?

    var body: some View {
        Button {
            Task {
                let restored = await viewModel.restore()
                if restored, let onRestored {
                    onRestored()
                } else {
                    showingResult = true
                }
            }
        } label: {
            if viewModel.isRestoring {
                ProgressView("Restoring purchases…")
            } else {
                Text("Restore Purchases")
            }
        }
        .disabled(viewModel.isRestoring)
        .alert("Restore Purchases", isPresented: $showingResult) {
            Button("OK") {}
        } message: {
            Text(viewModel.message)
        }
    }
}
