import SwiftUI

struct DeviceGridCardView: View {
    let viewData: DeviceListItemViewData
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewData.title)
                            .font(.caption)
                            .bold()
                            .lineLimit(1)
                            .foregroundStyle(viewData.isReachable ? .primary : .secondary)

                        Text(viewData.ipAddress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if viewData.showsLock {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                Spacer()

                HStack {
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

                    Spacer()
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
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(
            color: Color.primary.opacity(0.08),
            radius: 8,
            x: 0,
            y: 4
        )
    }
}
