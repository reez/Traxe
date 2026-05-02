import SwiftUI

struct DeviceGridCardView: View {
    let viewData: DeviceListItemViewData
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(viewData.title)
                            .font(.caption)
                            .bold()
                            .lineLimit(1)
                            .foregroundStyle(viewData.isReachable ? .primary : .secondary)
                            .layoutPriority(1)

                        Spacer(minLength: 4)

                        if let rankText = viewData.bestDifficultyRankText {
                            DeviceBestDifficultyRankBadgeView(
                                rankText: rankText,
                                isHighlighted: viewData.bestDifficultyRankIsHighlighted
                            )
                        }

                        if viewData.showsLock {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }

                    Text(viewData.ipAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 6) {
                    if viewData.showsBestDifficultyMetric,
                        let bestDifficultyValueText = viewData.bestDifficultyValueText,
                        let bestDifficultyUnitText = viewData.bestDifficultyUnitText
                    {
                        DeviceBestDifficultyMetricView(
                            valueText: bestDifficultyValueText,
                            unitText: bestDifficultyUnitText
                        )
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewData.hashrateValueText)
                            .font(.title)
                            .fontWeight(.bold)
                            .fontDesign(.rounded)
                            .contentTransition(.numericText())
                            .animation(.spring, value: viewData.hashrateValue)
                            .redacted(reason: viewData.showsPlaceholderHashrate ? .placeholder : [])
                            .foregroundStyle(viewData.isReachable ? .primary : .secondary)

                        Text(viewData.hashrateUnitText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    viewData.bestDifficultyRankIsHighlighted
                        ? Color.traxeGold.opacity(0.45)
                        : Color.primary.opacity(0.1),
                    lineWidth: 0.5
                )
        )
        .shadow(
            color: Color.primary.opacity(0.08),
            radius: 8,
            x: 0,
            y: 4
        )
    }
}

#Preview("Device Grid Cards") {
    HStack(spacing: 16) {
        DeviceGridCardView(
            viewData: PreviewFixtures.sampleDeviceListItemViewData,
            action: {}
        )

        DeviceGridCardView(
            viewData: PreviewFixtures.sampleLockedDeviceListItemViewData,
            action: {}
        )
    }
    .padding()
}
