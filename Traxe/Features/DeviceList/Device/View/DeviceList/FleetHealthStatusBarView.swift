import SwiftUI

struct FleetHealthStatusBarView: View {
    let total: Int
    let segments: [FleetHealthSignalSegment]

    private var visibleSegments: [FleetHealthSignalSegment] {
        segments.filter { $0.count > 0 }
    }

    private var animationSignature: String {
        visibleSegments.map { "\($0.id):\($0.count)" }.joined(separator: "|")
    }

    var body: some View {
        GeometryReader { proxy in
            let spacing = CGFloat(max(visibleSegments.count - 1, 0)) * 3
            let availableWidth = max(proxy.size.width - spacing, 0)

            HStack(spacing: 3) {
                ForEach(visibleSegments) { segment in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(segment.color)
                        .frame(
                            width: max(
                                availableWidth * CGFloat(segment.count) / CGFloat(max(total, 1)),
                                8
                            )
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.3), value: animationSignature)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}
