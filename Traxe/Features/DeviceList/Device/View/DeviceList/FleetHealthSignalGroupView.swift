import SwiftUI

struct FleetHealthSignalGroupView: View {
    let title: String?
    let segments: [FleetHealthSignalSegment]
    let barTotal: Int

    private var visibleSegments: [FleetHealthSignalSegment] {
        segments.filter { $0.count > 0 }
    }

    private var animationSignature: String {
        visibleSegments.map { "\($0.id):\($0.count)" }.joined(separator: "|")
    }

    var body: some View {
        if !visibleSegments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let title {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                FleetHealthStatusBarView(total: barTotal, segments: visibleSegments)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(visibleSegments) { segment in
                        FleetHealthSignalLineView(segment: segment)
                            .transition(
                                .opacity.combined(with: .move(edge: .top))
                            )
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: animationSignature)
        }
    }
}
