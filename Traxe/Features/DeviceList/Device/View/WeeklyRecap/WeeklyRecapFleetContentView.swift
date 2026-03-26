import SwiftUI

struct WeeklyRecapFleetContentView: View {
    let fleetRecaps: [WeeklyRecapFleetRecap]
    let expandedFleetDeviceIDs: Set<String>
    let areAllFleetSectionsExpanded: Bool
    let deviceHistoryEmptyStateText: String
    let toggleAllFleetSections: () -> Void
    let toggleFleetSection: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if fleetRecaps.count > 1 {
                HStack {
                    Spacer()
                    Button(action: toggleAllFleetSections) {
                        Text(areAllFleetSectionsExpanded ? "Collapse All" : "Expand All")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.traxeGold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Color.traxeGold.opacity(0.14),
                                in: Capsule(style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
            }

            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(fleetRecaps) { deviceRecap in
                    let isExpanded = expandedFleetDeviceIDs.contains(deviceRecap.id)
                    let poolAllocations = WeeklyRecapPoolAllocationBuilder.build(
                        from: deviceRecap.poolName,
                        totalHashrate: deviceRecap.recap?.averageHashrate
                            ?? deviceRecap.currentHashrate
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            toggleFleetSection(deviceRecap.id)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(deviceRecap.name)
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.traxeGold)
                                    Text(deviceRecap.id)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                    if !poolAllocations.isEmpty {
                                        VStack(alignment: .leading, spacing: 6) {
                                            ForEach(poolAllocations) { allocation in
                                                WeeklyRecapAllocationRowView(
                                                    labelText: allocation.name,
                                                    logoName: allocation.logoName,
                                                    estimatedHashrate: allocation.estimatedHashrate,
                                                    lastBlockHeight: nil
                                                )
                                            }
                                        }
                                        .padding(.top, 2)
                                    }
                                }

                                Spacer()

                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)

                        if isExpanded {
                            if let recap = deviceRecap.recap {
                                WeeklyRecapDetailContentView(
                                    recap: recap,
                                    showDateRange: false
                                )
                            } else {
                                WeeklyRecapMessageCardView(
                                    title: nil,
                                    message: deviceHistoryEmptyStateText
                                )
                            }
                        }
                    }
                    .id(deviceRecap.id)
                }
            }
            .padding(.top, 4)
        }
    }
}
