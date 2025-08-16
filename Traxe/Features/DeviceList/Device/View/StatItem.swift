import SwiftUI

struct StatItem: View {
    let label: String
    let value: Double
    let unit: String
    var isLoading: Bool
    var formatAsMillions: Bool = false
    let name: String
    var onRefresh: (() async -> Void)? = nil

    private var formattedValue: String {
        if value == 0.0 {
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
            Text(formattedValue)
                .fontDesign(.rounded)
                .font(.system(size: 64, weight: .bold))
                .contentTransition(.numericText())
                .animation(.default, value: formattedValue)
                .foregroundColor(.primary)
                .redacted(reason: value == 0.0 ? .placeholder : [])

            HStack(spacing: 6) {
                Text(displayUnit.uppercased())
                    .fontDesign(.rounded)
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)

                if let onRefresh = onRefresh {
                    Spacer()
                        .frame(width: 8)

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        //                        Button {
                        //                            Task {
                        //                                await onRefresh()
                        //                            }
                        //                        } label: {
                        //                            Image(systemName: "arrow.clockwise")
                        //                                .font(.system(size: 16))
                        //                                .foregroundStyle(.secondary)
                        //                        }
                        //                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

#Preview {
    StatItem(label: "Hash Rate", value: 100.1, unit: "unit", isLoading: false, name: "bolt.fill")
}
