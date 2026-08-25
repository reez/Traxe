import SwiftUI

struct DeviceGridHeaderView: View {
    @Binding var sortOption: DeviceGridSortOption

    var body: some View {
        let title = Text("Miners")
            .font(.title2)
            .fontWeight(.semibold)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        let sortPicker = Picker("Sort miners", selection: $sortOption) {
            ForEach(DeviceGridSortOption.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.automatic)
        .controlSize(.small)
        .tint(.primary)
        .fixedSize(horizontal: true, vertical: false)

        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                title
                Spacer(minLength: 8)
                sortPicker
            }

            VStack(alignment: .leading, spacing: 8) {
                title
                HStack {
                    Spacer(minLength: 0)
                    sortPicker
                }
            }
        }
    }
}

#Preview("Device Grid Header - Default") {
    @Previewable @State var sortOption = DeviceGridSortOption.savedOrder

    DeviceGridHeaderView(sortOption: $sortOption)
        .padding()
}

#Preview("Device Grid Header - Scoreboard") {
    @Previewable @State var sortOption = DeviceGridSortOption.scoreboard

    DeviceGridHeaderView(sortOption: $sortOption)
        .padding()
}
