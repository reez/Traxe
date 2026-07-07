import SwiftUI

struct LargeFleetHashrateHeader: View {
    let minerName: String?
    let hashrateValue: String
    let hashrateUnit: String
    let updatedAt: Date
    let isRedacted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let minerName {
                    Text(minerName.uppercased())
                } else {
                    Text("HASH RATE")
                }
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(Color.traxeGold)
            .lineLimit(1)
            .padding(.bottom, 8)

            Text(hashrateValue)
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())
                .redacted(reason: isRedacted ? .placeholder : [])

            Text(hashrateUnit)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.top, -6)

            Text("at \(updatedAt, style: .time)")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
        .fontDesign(.rounded)
        .foregroundStyle(.primary)
    }
}
