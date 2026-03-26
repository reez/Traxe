import SwiftUI

struct WeeklyRecapAllocationRowView: View {
    let labelText: String
    let logoName: String?
    let estimatedHashrate: Double?
    let lastBlockHeight: Int?

    var body: some View {
        HStack(spacing: 8) {
            PoolLogoView(logoName: logoName, size: 12)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Text(labelText)
                    .font(estimatedHashrate == nil ? .caption2 : .caption)
                    .foregroundStyle(.secondary)

                if let lastBlockHeight {
                    WeeklyRecapLastBlockRevealView(lastBlockHeight: lastBlockHeight)
                }
            }

            if let estimatedHashrate {
                Spacer()

                Text(WeeklyRecapChartPresenter.formattedHashrate(estimatedHashrate))
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        }
    }
}
