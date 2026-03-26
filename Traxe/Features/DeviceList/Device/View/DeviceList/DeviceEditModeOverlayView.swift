import SwiftUI

struct DeviceEditModeOverlayView: View {
    let viewModel: DeviceListViewModel
    let subscriptionAccessPolicy: SubscriptionAccessPolicy

    var body: some View {
        VStack {
            List {
                ForEach(viewModel.savedDevices.indices, id: \.self) { index in
                    let device = viewModel.savedDevices[index]
                    let viewData = DeviceListItemPresenter.makeViewData(
                        device: device,
                        metrics: viewModel.deviceMetrics[device.ipAddress],
                        index: index,
                        reachableIPs: viewModel.reachableIPs,
                        isLoadingAggregatedStats: viewModel.isLoadingAggregatedStats,
                        subscriptionAccessPolicy: subscriptionAccessPolicy
                    )

                    DeviceEditModeRowView(
                        position: index + 1,
                        viewData: viewData
                    )
                }
                .onMove(perform: viewModel.reorderDevices)
                .onDelete(perform: viewModel.deleteDevice)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .transition(.opacity)
    }
}
