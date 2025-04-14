import SwiftUI

struct DangerZoneSection: View {
    let onRestart: () -> Void

    var body: some View {
        Section {
            Button("Restart Device", role: .destructive, action: onRestart)
        } header: {
            Text("Danger Zone")
        }
    }
}

#Preview {
    DangerZoneSection(onRestart: {})
}
