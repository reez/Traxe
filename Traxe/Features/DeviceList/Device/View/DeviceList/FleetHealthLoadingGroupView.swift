import SwiftUI

struct FleetHealthLoadingGroupView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(height: 10)
        }
        .accessibilityHidden(true)
    }
}
