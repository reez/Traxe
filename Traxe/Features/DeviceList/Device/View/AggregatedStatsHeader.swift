import SwiftUI

struct AggregatedStatsHeader: View {
    @ObservedObject var viewModel: DeviceListViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text("Total")
                .font(.largeTitle)
                .fontWeight(.bold)

            StatItem(
                label: "Hash Rate",
                value: viewModel.totalHashRate,
                unit: "TH/s",
                isLoading: viewModel.isLoadingAggregatedStats || viewModel.totalHashRate == 0.0,
                name: "bolt.fill"
            )
            .frame(maxWidth: .infinity)
            StatItem(
                label: "Power",
                value: viewModel.totalPower,
                unit: "W",
                isLoading: viewModel.isLoadingAggregatedStats || viewModel.totalPower == 0.0,
                name: "battery.100percent.bolt"
            )
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(10)
        .shadow(radius: 1)
    }
}

#Preview {
    AggregatedStatsHeader(viewModel: .init())
}
