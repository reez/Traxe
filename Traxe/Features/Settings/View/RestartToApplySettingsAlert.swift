import SwiftUI

extension View {
    /// Offers a restart after a save that the miner only applies while booting, such as a pool
    /// or hostname change on ESP-Miner before 2.15. "Later" keeps the saved values and leaves
    /// the miner running its current configuration until someone restarts it.
    func restartToApplySettingsAlert(
        isPresented: Binding<Bool>,
        message: String,
        restart: @escaping () async -> Void,
        dismiss: @escaping () -> Void
    ) -> some View {
        alert("Restart Miner to Apply?", isPresented: isPresented) {
            Button("Restart", role: .destructive) {
                Task { await restart() }
                dismiss()
            }
            Button("Later", role: .cancel, action: dismiss)
        } message: {
            Text(message)
        }
    }
}
