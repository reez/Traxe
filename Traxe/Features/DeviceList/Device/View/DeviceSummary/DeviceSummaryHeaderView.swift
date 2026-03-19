import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

struct DeviceSummaryHeaderView: View {
    let deviceName: String
    let poolRows: [PoolDisplayLineViewData]

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 10) {
                Text(deviceName)
                    .foregroundStyle(.secondary)

                if !poolRows.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(poolRows) { row in
                            HStack(spacing: 6) {
                                PoolLogoView(
                                    logoName: row.logoName,
                                    size: UIFont.preferredFont(forTextStyle: .caption2).pointSize
                                )
                                Text(row.text)
                            }
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)

            Spacer()
        }
        .padding()
    }
}
