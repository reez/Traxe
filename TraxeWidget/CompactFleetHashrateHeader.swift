import SwiftUI

/// Keeps room for the alert when the widget shows several miner states.
struct CompactFleetHashrateHeader: View {
    let minerName: String?
    let hashrateValue: String
    let hashrateUnit: String
    let updatedAt: Date?
    let isRedacted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let minerName {
                    Text(minerName.uppercased())
                } else {
                    Text("HASH RATE")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.traxeGold)
            .lineLimit(1)

            HStack(alignment: .firstTextBaseline) {
                Text(hashrateValue)
                    .font(.largeTitle.bold())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .redacted(reason: isRedacted ? .placeholder : [])

                Text(hashrateUnit)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let updatedAt {
                Text("Last reading \(updatedAt, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fontDesign(.rounded)
        .foregroundStyle(.primary)
    }
}
