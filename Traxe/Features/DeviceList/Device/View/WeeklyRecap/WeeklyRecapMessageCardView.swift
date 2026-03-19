import SwiftUI

struct WeeklyRecapMessageCardView: View {
    let title: String?
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: title == nil ? 0 : 10) {
            if let title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .padding(.horizontal)
    }
}
