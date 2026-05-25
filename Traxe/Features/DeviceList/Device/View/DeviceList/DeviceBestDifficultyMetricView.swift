import SwiftUI

struct DeviceBestDifficultyMetricView: View {
    let valueText: String
    let unitText: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(valueText)
                .fontWeight(.semibold)
                .fontDesign(.rounded)

            Text(unitText)
                .fontWeight(.medium)

            Text("Best Diff")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Best diff \(valueText) \(unitText)")
    }
}

#Preview("Best Diff Metric") {
    DeviceBestDifficultyMetricView(valueText: "4.07", unitText: "G")
        .padding()
}
