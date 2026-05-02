import SwiftUI

struct DeviceEditModeOverlayView: View {
    let viewModel: DeviceListViewModel
    let sortOption: DeviceGridSortOption
    let subscriptionAccessPolicy: SubscriptionAccessPolicy

    var body: some View {
        VStack {
            List {
                if sortOption == .savedOrder {
                    ForEach(gridItems.indices, id: \.self) { index in
                        row(at: index)
                    }
                    .onMove(perform: viewModel.reorderDevices)
                    .onDelete(perform: deleteItems)
                } else {
                    ForEach(gridItems.indices, id: \.self) { index in
                        row(at: index)
                    }
                    .onDelete(perform: deleteItems)
                }
            }
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .transition(.opacity)
    }

    private var gridItems: [DeviceGridItem] {
        DeviceGridPresenter.makeItems(
            devices: viewModel.savedDevices,
            metricsByIP: viewModel.deviceMetrics,
            sortOption: sortOption
        )
    }

    private func row(at index: Int) -> DeviceEditModeRowView {
        let item = gridItems[index]
        let device = item.device
        let viewData = DeviceListItemPresenter.makeViewData(
            device: device,
            metrics: viewModel.deviceMetrics[device.ipAddress],
            index: item.savedDeviceIndex,
            reachableIPs: viewModel.reachableIPs,
            isLoadingAggregatedStats: viewModel.isLoadingAggregatedStats,
            subscriptionAccessPolicy: subscriptionAccessPolicy,
            bestDifficultyRank: item.bestDifficultyRank,
            sortOption: sortOption
        )

        return DeviceEditModeRowView(
            position: index + 1,
            viewData: viewData
        )
    }

    private func deleteItems(at offsets: IndexSet) {
        let ipAddresses = Set(offsets.map { gridItems[$0].device.ipAddress })
        viewModel.deleteDevices(withIPAddresses: ipAddresses)
    }
}

#Preview("Edit Mode Overlay") {
    let viewModel = PreviewFixtures.makeDeviceListViewModel()

    DeviceEditModeOverlayView(
        viewModel: viewModel,
        sortOption: .savedOrder,
        subscriptionAccessPolicy: PreviewFixtures.sampleSubscriptionAccessPolicy
    )
}
