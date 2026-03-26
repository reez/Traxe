import SwiftUI

struct DeviceGridSectionView: View {
    let viewModel: DeviceListViewModel
    let subscriptionAccessPolicy: SubscriptionAccessPolicy
    let showFleetWeeklyRecap: () -> Void
    let handleSelection: (SavedDevice, Bool) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        LazyVStack(spacing: 40) {
            Spacer().frame(height: 10)

            if viewModel.savedDevices.count > 1 {
                AggregatedStatsHeader(viewModel: viewModel)
            }

            if !viewModel.savedDevices.isEmpty {
                WeeklyRecapNavigationTile(viewData: .fleet, action: showFleetWeeklyRecap)
                    .padding(.top, viewModel.savedDevices.count > 1 ? -46 : 0)
                    .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("Miners")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.horizontal)

                LazyVGrid(columns: columns, spacing: 12) {
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

                        DeviceGridCardView(viewData: viewData) {
                            handleSelection(device, viewData.isAccessible)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 40)
    }
}
