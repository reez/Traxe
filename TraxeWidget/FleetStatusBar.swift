import SwiftUI

struct FleetStatusBar: View {
    let status: WidgetFleetStatus

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                segment(
                    color: FleetStatusPalette.online,
                    count: status.online,
                    availableWidth: proxy.size.width
                )
                segment(
                    color: FleetStatusPalette.paused,
                    count: status.paused,
                    availableWidth: proxy.size.width
                )
                segment(
                    color: FleetStatusPalette.offline,
                    count: status.offline,
                    availableWidth: proxy.size.width
                )
                segment(
                    color: FleetStatusPalette.unknown,
                    count: status.unknown,
                    availableWidth: proxy.size.width
                )
            }
            .background(.quaternary, in: .capsule)
            .clipShape(.capsule)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private func segment(color: Color, count: Int, availableWidth: CGFloat) -> some View {
        color.frame(width: segmentWidth(count: count, availableWidth: availableWidth))
    }

    private func segmentWidth(count: Int, availableWidth: CGFloat) -> CGFloat {
        guard status.total > 0 else { return 0 }
        return availableWidth * CGFloat(count) / CGFloat(status.total)
    }
}
