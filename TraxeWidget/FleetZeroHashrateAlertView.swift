import SwiftUI

struct FleetZeroHashrateAlertView: View {
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alerts")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Circle()
                    .fill(.secondary)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)

                Text(count, format: .number)
                    .fontWeight(.semibold)
                    .monospacedDigit()

                Text("Hashrate = 0")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }
}
