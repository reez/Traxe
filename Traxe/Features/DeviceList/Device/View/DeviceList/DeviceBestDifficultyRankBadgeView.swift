import SwiftUI

struct DeviceBestDifficultyRankBadgeView: View {
    let rankText: String
    let isHighlighted: Bool

    var body: some View {
        Text(rankText)
            .font(.caption2)
            .fontWeight(.semibold)
            .fontDesign(.rounded)
            .foregroundStyle(isHighlighted ? Color.traxeGold : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                isHighlighted
                    ? Color.traxeGold.opacity(0.14)
                    : Color(uiColor: .tertiarySystemFill),
                in: Capsule()
            )
            .accessibilityLabel("Best diff rank \(rankText)")
    }
}

#Preview("Best Diff Rank Badge") {
    HStack {
        DeviceBestDifficultyRankBadgeView(rankText: "#1", isHighlighted: true)
        DeviceBestDifficultyRankBadgeView(rankText: "#2", isHighlighted: false)
    }
    .padding()
}
