import SwiftUI

struct DangerZoneSection: View {
    let onRestart: () -> Void
    let onDelete: () -> Void
    let canDeleteMiner: Bool

    var body: some View {
        Section {
            Button("Restart Miner", role: .destructive, action: onRestart)
            Button("Delete Miner", role: .destructive, action: onDelete)
                .disabled(!canDeleteMiner)
        } header: {
            Text("Danger Zone")
        }
    }
}

#Preview {
    DangerZoneSection(
        onRestart: {},
        onDelete: {},
        canDeleteMiner: true
    )
}
