import SwiftUI

struct DeviceSummaryHashrateSectionView: View {
    let historicalData: [HistoricalDataPoint]

    var body: some View {
        SparklineView(
            data: historicalData,
            valueKey: \.hashrate,
            style: .bars,
            barAlignment: .leading
        )
        .frame(height: 60)
    }
}

#Preview("Device Summary Hashrate") {
    DeviceSummaryHashrateSectionView(
        historicalData: PreviewFixtures.sampleHistoricalData()
    )
    .padding()
}
