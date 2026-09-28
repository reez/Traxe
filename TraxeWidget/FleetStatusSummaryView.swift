import SwiftUI

struct FleetStatusSummaryView: View {
    let status: WidgetFleetStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(status.total, format: .number)
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()

                if status.total == 1 {
                    Text("miner")
                } else {
                    Text("miners")
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                if status.online > 0 {
                    FleetStatusRow(
                        count: status.online,
                        title: "Online",
                        color: FleetStatusPalette.online
                    )
                }
                if status.paused > 0 {
                    FleetStatusRow(
                        count: status.paused,
                        title: "Paused",
                        color: FleetStatusPalette.paused
                    )
                }
                if status.offline > 0 {
                    FleetStatusRow(
                        count: status.offline,
                        title: "Offline",
                        color: FleetStatusPalette.offline
                    )
                }
                if status.unknown > 0 {
                    FleetStatusRow(
                        count: status.unknown,
                        title: "Unknown",
                        color: FleetStatusPalette.unknown
                    )
                }
            }

            FleetStatusBar(status: status)
        }
        .fontDesign(.rounded)
        .accessibilityElement(children: .combine)
    }
}
