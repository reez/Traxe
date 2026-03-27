import SwiftUI

struct WeeklyRecapStatCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }
}

#Preview("Weekly Recap Stat Card") {
    WeeklyRecapStatCard(
        title: "Average Hash Rate",
        value: "5.1 TH/s",
        subtitle: "Across 21 samples"
    )
    .padding()
}
