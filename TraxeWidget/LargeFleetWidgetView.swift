import SwiftUI

struct LargeFleetWidgetView: View {
    let minerName: String?
    let hashrateValue: String
    let hashrateUnit: String
    let updatedAt: Date?
    let isRedacted: Bool
    let status: WidgetFleetStatus
    var metricStatus: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let visibleStateCount = [status.online, status.paused, status.offline, status.unknown]
                .filter { $0 > 0 }.count
            if status.zeroHashrate > 0 && visibleStateCount > 2 {
                CompactFleetHashrateHeader(
                    minerName: minerName,
                    hashrateValue: hashrateValue,
                    hashrateUnit: hashrateUnit,
                    updatedAt: updatedAt,
                    isRedacted: isRedacted
                )
            } else {
                LargeFleetHashrateHeader(
                    minerName: minerName,
                    hashrateValue: hashrateValue,
                    hashrateUnit: hashrateUnit,
                    updatedAt: updatedAt,
                    isRedacted: isRedacted
                )
            }

            Text(metricStatus)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            FleetStatusSummaryView(status: status)
        }
        .padding()
    }
}
