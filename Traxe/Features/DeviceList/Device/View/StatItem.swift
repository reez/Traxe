import SwiftUI

struct StatItem: View {
    let label: String
    let value: Double
    let unit: String
    var isLoading: Bool
    var formatAsMillions: Bool = false
    let name: String

    private var formattedValue: String {
        if isLoading {
            return "---"
        }

        if label == "Hash Rate" {
            let displayValue = value >= 1000 ? value / 1000 : value
            return String(format: "%.1f", displayValue)
        } else {
            let displayValue = formatAsMillions ? value / 1_000_000 : value
            return String(format: "%.1f", displayValue)
        }
    }

    private var displayUnit: String {
        if label == "Hash Rate" {
            return value >= 1000 ? "TH/s" : "GH/s"
        }
        return unit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: name)
                    .font(.caption)
                Text(label).bold()
                Spacer()
            }
            .foregroundStyle(.primary)
            .font(.subheadline)
            HStack(alignment: .firstTextBaseline) {
                Text(formattedValue)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .contentTransition(.numericText())
                    .animation(.default, value: formattedValue)
                    .foregroundColor(isLoading ? .secondary : .primary)
                    .redacted(reason: isLoading ? .placeholder : [])
                Text(displayUnit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    StatItem(label: "Hash Rate", value: 100.1, unit: "unit", isLoading: false, name: "bolt.fill")
}
