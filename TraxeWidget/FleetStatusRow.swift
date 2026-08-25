import SwiftUI

struct FleetStatusRow: View {
    let count: Int
    let title: LocalizedStringResource
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            Text(count, format: .number)
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()

            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}
