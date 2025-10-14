import SwiftUI

struct DeviceDetailView: View {
    let miner: WatchMinerSummary

    var body: some View {
        List {

            Section {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(miner.hashrateValue)
                        .font(.title3)
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                    if !miner.hashrateUnit.isEmpty {
                        Text(miner.hashrateUnit)
                            .font(.caption2)
                            .fontDesign(.rounded)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Total Hash Rate")
                //                    .font(.caption2)
                //                    .fontDesign(.rounded)
                //                    .foregroundStyle(.secondary)
            } footer: {
                if let updated = miner.lastUpdated {
                    Text("Updated \(updated, style: .time)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            //            footer: {
            //                if let updated = miner.lastUpdated {
            //                    Text("Updated \(updated, style: .time)")
            //                        .font(.caption2)
            //                        .foregroundStyle(.tertiary)
            //                }
            //            }

            //            Section {
            //                VStack(alignment: .leading, spacing: 4) {
            //                    Text(miner.name)
            //                        .font(.title3)
            //                        .fontWeight(.semibold)
            //                        .fontDesign(.rounded)
            //                    Text(miner.ipAddress)
            //                        .font(.caption2)
            //                        .foregroundStyle(.secondary)
            //                }
            //                .padding(.vertical, 4)
            //            }

            Section("") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(miner.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .fontDesign(.rounded)
                }
                .padding(.vertical, 4)
                //                HStack(alignment: .lastTextBaseline, spacing: 4) {
                //                    Text(miner.hashrateValue)
                //                        .font(.title3)
                //                        .fontWeight(.bold)
                //                        .fontDesign(.rounded)
                //                    if !miner.hashrateUnit.isEmpty {
                //                        Text(miner.hashrateUnit)
                //                            .font(.caption2)
                //                            .fontDesign(.rounded)
                //                            .foregroundStyle(.secondary)
                //                    }
                //                }
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(miner.ipAddress)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .fontDesign(.rounded)
                }

                //                if let updated = miner.lastUpdated {
                //                    Text("Updated \(updated, style: .time)")
                //                        .font(.caption2)
                //                        .foregroundStyle(.tertiary)
                //                }
            }
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    DeviceDetailView(
        miner: WatchMinerSummary(
            id: "192.168.1.10",
            name: "bitaxe",
            ipAddress: "192.168.1.10",
            hashrateValue: "495.1",
            hashrateUnit: "GH/s",
            lastUpdated: Date()
        )
    )
}
