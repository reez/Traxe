import SwiftUI

struct DangerZoneSection: View {
    let onRestart: () -> Void

    var body: some View {
        Section {
            Button("Restart Miner", role: .destructive, action: onRestart)
        } header: {
            Text("Danger Zone")
        }
    }
}

#Preview {
    DangerZoneSection(onRestart: {})
}
