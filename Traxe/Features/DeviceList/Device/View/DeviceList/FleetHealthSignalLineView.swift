import SwiftUI

struct FleetHealthSignalLineView: View {
    let segment: FleetHealthSignalSegment

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(segment.color)
                .frame(width: 7, height: 7)

            Text(segment.count.formatted())
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(segment.title)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
