import SwiftUI

struct DeviceSummaryHashrateSectionView: View {
    let historicalData: [HistoricalDataPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hash Rate")
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .center, spacing: 8) {
                Spacer()
                SparklineView(
                    data: historicalData,
                    valueKey: \.hashrate,
                    style: .bars
                )
                .frame(height: 60)
                Spacer()
            }
        }
    }
}
