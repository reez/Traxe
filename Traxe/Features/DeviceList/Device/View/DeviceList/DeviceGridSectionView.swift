import SwiftUI

struct DeviceGridSectionView: View {
    @Bindable var viewModel: DeviceListViewModel
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
                AggregatedStatsHeader(
                    viewModel: viewModel,
                    showFleetWeeklyRecap: showFleetWeeklyRecap
                )
            } else if !viewModel.savedDevices.isEmpty {
                WeeklyRecapNavigationTile(viewData: .fleet, action: showFleetWeeklyRecap)
                    .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 16) {
                DeviceGridHeaderView(sortOption: $viewModel.deviceGridSortOption)
                    .padding(.horizontal)

                let gridItems = DeviceGridPresenter.makeItems(
                    devices: viewModel.savedDevices,
                    metricsByIP: viewModel.deviceMetrics,
                    sortOption: viewModel.deviceGridSortOption
                )

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(gridItems) { item in
                        let device = item.device
                        let viewData = DeviceListItemPresenter.makeViewData(
                            device: device,
                            metrics: viewModel.deviceMetrics[device.ipAddress],
                            index: item.savedDeviceIndex,
                            reachableIPs: viewModel.reachableIPs,
                            isLoadingAggregatedStats: viewModel.isLoadingAggregatedStats,
                            subscriptionAccessPolicy: subscriptionAccessPolicy,
                            bestDifficultyRank: item.bestDifficultyRank,
                            sortOption: viewModel.deviceGridSortOption
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

#Preview("Device Grid Section") {
    let viewModel = PreviewFixtures.makeDeviceListViewModel()

    ScrollView {
        DeviceGridSectionView(
            viewModel: viewModel,
            subscriptionAccessPolicy: PreviewFixtures.sampleSubscriptionAccessPolicy,
            showFleetWeeklyRecap: {},
            handleSelection: { _, _ in }
        )
    }
}
