import SwiftUI

struct LargeFleetWidgetView: View {
    let minerName: String?
    let hashrateValue: String
    let hashrateUnit: String
    let updatedAt: Date
    let isRedacted: Bool
    let status: WidgetFleetStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LargeFleetHashrateHeader(
                minerName: minerName,
                hashrateValue: hashrateValue,
                hashrateUnit: hashrateUnit,
                updatedAt: updatedAt,
                isRedacted: isRedacted
            )

            Spacer(minLength: 12)

            FleetStatusSummaryView(status: status)
        }
        .padding()
    }
}
