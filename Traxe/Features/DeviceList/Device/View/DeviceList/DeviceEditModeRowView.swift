import SwiftUI

struct DeviceEditModeRowView: View {
    let position: Int
    let viewData: DeviceListItemViewData

    var body: some View {
        HStack(alignment: .center) {
            Text("\(position)")
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(position < 10 ? .primary : .secondary)
                .frame(width: 30)

            VStack(alignment: .leading) {
                Text(viewData.title)
                    .font(.headline)
                Text(viewData.ipAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let summaryHashrateText = viewData.summaryHashrateText {
                    Text(summaryHashrateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .font(.title2)
        }
        .padding(.vertical, 8)
    }
}
