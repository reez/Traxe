import SwiftUI

struct DeviceGridHeaderView: View {
    @Binding var sortOption: DeviceGridSortOption

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Miners")
                .font(.title2)
                .fontWeight(.semibold)
                .lineLimit(1)

            Spacer(minLength: 8)

            Picker("Sort miners", selection: $sortOption) {
                ForEach(DeviceGridSortOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.automatic)
            .controlSize(.small)
            .tint(.primary)
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
