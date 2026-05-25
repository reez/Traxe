import SwiftUI

struct FleetHealthLoadingGroupView: View {
    private let indicatorColor = Color(uiColor: .tertiarySystemFill)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(indicatorColor)
                .frame(height: 10)

            VStack(alignment: .leading, spacing: 6) {
                loadingLine(width: 78)
                loadingLine(width: 86)
            }
        }
        .accessibilityHidden(true)
    }

    private func loadingLine(width: CGFloat) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 7, height: 7)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(indicatorColor)
                .frame(width: width, height: 14)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
