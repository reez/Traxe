import SwiftUI

struct WeeklyRecapContextHeaderView: View {
    let scope: WeeklyRecapView.Scope
    let weekTitleText: String
    let fleetPoolAllocations: [WeeklyRecapPoolAllocation]
    let latestBlockHeightsByPoolSlug: [String: Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(weekTitleText)
                .font(.largeTitle)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            switch scope {
            case .device(_, let deviceName, let poolName):
                let devicePoolAllocations = WeeklyRecapPoolAllocationBuilder.build(
                    from: poolName,
                    totalHashrate: 0
                )

                Text(deviceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !devicePoolAllocations.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(devicePoolAllocations) { allocation in
                            WeeklyRecapAllocationRowView(
                                labelText: devicePoolLabel(for: allocation),
                                logoName: allocation.logoName,
                                estimatedHashrate: nil,
                                lastBlockHeight: nil
                            )
                        }
                    }
                    .padding(.top, 2)
                } else if let poolName, !poolName.isEmpty {
                    Text(poolName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .fleet(let devices):
                VStack(alignment: .leading, spacing: 10) {
                    let names = devices.map(\.name).filter { !$0.isEmpty }

                    headerSectionLabel("Miners")

                    VStack(alignment: .leading, spacing: 2) {
                        if names.isEmpty {
                            Text("No miners")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(names.indices, id: \.self) { index in
                                Text(names[index])
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !fleetPoolAllocations.isEmpty {
                        headerSectionLabel("Pools")

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(fleetPoolAllocations) { allocation in
                                WeeklyRecapAllocationRowView(
                                    labelText: allocation.name,
                                    logoName: allocation.logoName,
                                    estimatedHashrate: allocation.estimatedHashrate,
                                    lastBlockHeight: allocation.poolSlug.flatMap {
                                        latestBlockHeightsByPoolSlug[$0]
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    private func headerSectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
    }

    private func devicePoolLabel(for allocation: WeeklyRecapPoolAllocation) -> String {
        guard let configuredPercent = allocation.configuredPercent else {
            return allocation.name
        }

        return
            "\(allocation.name) (\(WeeklyRecapChartPresenter.formattedPoolPercent(configuredPercent))%)"
    }
}
