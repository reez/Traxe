import Observation
import SwiftUI

struct AggregatedStatsHeader: View {
    @Bindable var viewModel: DeviceListViewModel
    let showFleetWeeklyRecap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Total Hash Rate")
                    .font(.title2)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 8) {
                    // Keep the UI calm during refresh: no inline spinner here.
                    StatItem(
                        label: "Hash Rate",
                        value: viewModel.totalHashRate,
                        unit: "TH/s",
                        isLoading: false,
                        name: "bolt.fill"
                    )

                    //                Text("Updated: \(viewModel.lastDataUpdate, style: .time)")
                    //                    .font(.caption2)
                    //                    .foregroundStyle(.tertiary)
                    //                    .padding(.leading, 16)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                //            .background {
                //                if #available(iOS 26.0, *) {
                //                    ConcentricRectangle(corners: .concentric(minimum: 20))
                //                        .fill(Color(.secondarySystemBackground))
                //                    //                        .fill(
                //                    //                            LinearGradient(
                //                    //                                colors: [
                //                    //                                    Color(.tertiarySystemBackground),
                //                    //                                    Color(.secondarySystemBackground)
                //                    //                                ],
                //                    //                                startPoint: .bottom,
                //                    //                                endPoint: .top
                //                    //                            )
                //                    //                        )
                //                    //                        .overlay(
                //                    //                            ConcentricRectangle(corners: .concentric(minimum: 20))
                //                    //                                .fill(
                //                    //                                    LinearGradient(
                //                    //                                        colors: [
                //                    //                                            Color.traxeGold.opacity(0.08),
                //                    //                                            Color.clear
                //                    //                                        ],
                //                    //                                        startPoint: .bottom,
                //                    //                                        endPoint: .top
                //                    //                                    )
                //                    //                                )
                //                    //                        )
                //                } else {
                //                    RoundedRectangle(cornerRadius: 20)
                //                        .fill(Color(.secondarySystemBackground))
                //                    //                        .fill(
                //                    //                            LinearGradient(
                //                    //                                colors: [
                //                    //                                    Color(.tertiarySystemBackground),
                //                    //                                    Color(.secondarySystemBackground)
                //                    //                                ],
                //                    //                                startPoint: .bottom,
                //                    //                                endPoint: .top
                //                    //                            )
                //                    //                        )
                //                    //                        .overlay(
                //                    //                            RoundedRectangle(cornerRadius: 20)
                //                    //                                .fill(
                //                    //                                    LinearGradient(
                //                    //                                        colors: [
                //                    //                                            Color.traxeGold.opacity(0.08),
                //                    //                                            Color.clear
                //                    //                                        ],
                //                    //                                        startPoint: .bottom,
                //                    //                                        endPoint: .top
                //                    //                                    )
                //                    //                                )
                //                    //                        )
                //                }
                //            }
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
            }

            VStack(alignment: .leading, spacing: 16) {
                if AIFeatureFlags.isAvailable,
                    AIFeatureFlags.isEnabledByUser,
                    viewModel.savedDevices.count > 1
                {
                    Text("Summary")
                        .font(.title2)
                        .fontWeight(.semibold)

                    // Generate from cached metrics if not yet present
                    if let fleetSummary = viewModel.fleetAISummary {
                        // Highlight value tokens (hash rate, temps, watts, percents)
                        let highlighted = fleetSummary.content.highlightingValues(color: .traxeGold)
                        Text(highlighted)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.interpolate)
                            .animation(.easeInOut(duration: 0.4), value: fleetSummary.content)
                    } else {
                        // Placeholder text to avoid layout jump on first load
                        Text("Generating insights for your miners…")
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(.secondary)
                    }
                }

                FleetHealthCardView(
                    snapshot: viewModel.fleetHealthSnapshot,
                    isLoading: viewModel.isFleetHealthLoading,
                    isRefreshing: viewModel.isFleetHealthRefreshing
                )

                WeeklyRecapNavigationTile(viewData: .fleet, action: showFleetWeeklyRecap)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

#Preview {
    let mockDefaults = makeAggregatedStatsPreviewDefaults()
    let mockDevices = [
        SavedDevice(name: "Living Room", ipAddress: "192.168.1.101"),
        SavedDevice(name: "Office", ipAddress: "192.168.1.102"),
        SavedDevice(name: "Bedroom", ipAddress: "192.168.1.103"),
        SavedDevice(name: "Kitchen", ipAddress: "192.168.1.104"),
        SavedDevice(name: "Garage", ipAddress: "192.168.1.105"),
        SavedDevice(name: "Basement", ipAddress: "192.168.1.106"),
        SavedDevice(name: "Attic", ipAddress: "192.168.1.107"),
        SavedDevice(name: "Porch", ipAddress: "192.168.1.108"),
        SavedDevice(name: "Shed", ipAddress: "192.168.1.109"),
        SavedDevice(name: "Workshop", ipAddress: "192.168.1.110"),
        SavedDevice(name: "Server Room", ipAddress: "192.168.1.111"),
        SavedDevice(name: "Lab", ipAddress: "192.168.1.112"),
        SavedDevice(name: "Studio", ipAddress: "192.168.1.113"),
        SavedDevice(name: "Closet", ipAddress: "192.168.1.114"),
        SavedDevice(name: "Pantry", ipAddress: "192.168.1.115"),
    ]

    let encoder = JSONEncoder()
    if let data = try? encoder.encode(mockDevices) {
        mockDefaults.set(data, forKey: "savedDevices")
    }

    let viewModel = DeviceListViewModel(defaults: mockDefaults)

    // Add mock device metrics
    viewModel.deviceMetrics = [
        "192.168.1.101": DeviceMetrics(
            hashrate: 485.2,
            temperature: 65,
            bestDifficulty: 1.2,
            poolURL: "public-pool.io"
        ),
        "192.168.1.102": DeviceMetrics(
            hashrate: 521.8,
            temperature: 68,
            bestDifficulty: 1.5,
            poolURL: "mining-pool.com"
        ),
        "192.168.1.103": DeviceMetrics(
            hashrate: 467.3,
            temperature: 62,
            bestDifficulty: 1.1,
            poolURL: "crypto-pool.net"
        ),
        "192.168.1.104": DeviceMetrics(
            hashrate: 502.7,
            temperature: 70,
            bestDifficulty: 1.4,
            poolURL: "hash-pool.org"
        ),
        "192.168.1.105": DeviceMetrics(
            hashrate: 445.9,
            temperature: 64,
            bestDifficulty: 0.9,
            poolURL: "mine-pool.io"
        ),
        "192.168.1.106": DeviceMetrics(
            hashrate: 489.1,
            temperature: 66,
            bestDifficulty: 1.3,
            poolURL: "pool-hub.com"
        ),
        "192.168.1.107": DeviceMetrics(
            hashrate: 512.4,
            temperature: 69,
            bestDifficulty: 1.6,
            poolURL: "fast-pool.net"
        ),
        "192.168.1.108": DeviceMetrics(
            hashrate: 473.6,
            temperature: 63,
            bestDifficulty: 1.0,
            poolURL: "super-pool.org"
        ),
        "192.168.1.109": DeviceMetrics(
            hashrate: 456.8,
            temperature: 61,
            bestDifficulty: 0.8,
            poolURL: "mega-pool.io"
        ),
        "192.168.1.110": DeviceMetrics(
            hashrate: 498.2,
            temperature: 67,
            bestDifficulty: 1.2,
            poolURL: "elite-pool.com"
        ),
        "192.168.1.111": DeviceMetrics(
            hashrate: 506.3,
            temperature: 66,
            bestDifficulty: 1.4,
            poolURL: "pro-pool.net"
        ),
        "192.168.1.112": DeviceMetrics(
            hashrate: 478.9,
            temperature: 64,
            bestDifficulty: 1.1,
            poolURL: "turbo-pool.org"
        ),
        "192.168.1.113": DeviceMetrics(
            hashrate: 492.5,
            temperature: 68,
            bestDifficulty: 1.3,
            poolURL: "speed-pool.com"
        ),
        "192.168.1.114": DeviceMetrics(
            hashrate: 515.7,
            temperature: 69,
            bestDifficulty: 1.5,
            poolURL: "ultra-pool.io"
        ),
        "192.168.1.115": DeviceMetrics(
            hashrate: 463.2,
            temperature: 63,
            bestDifficulty: 0.9,
            poolURL: "power-pool.net"
        ),
    ]

    // Set total hash rate
    viewModel.totalHashRate = 7.35
    viewModel.isLoadingAggregatedStats = false

    return aggregatedStatsHeaderPreviewContent(viewModel: viewModel)
}

#Preview("Aggregated Stats - Loading Status") {
    aggregatedStatsHeaderPreviewContent(
        viewModel: makeAggregatedStatsHeaderPreviewViewModel(
            onlineCount: 5,
            offlineCount: 2,
            isLoadingStatus: true
        )
    )
}

#Preview("Aggregated Stats - Five Online Two Offline") {
    aggregatedStatsHeaderPreviewContent(
        viewModel: makeAggregatedStatsHeaderPreviewViewModel(
            onlineCount: 5,
            offlineCount: 2,
            isLoadingStatus: false
        )
    )
}

#Preview("Aggregated Stats - Four Online Three Offline") {
    aggregatedStatsHeaderPreviewContent(
        viewModel: makeAggregatedStatsHeaderPreviewViewModel(
            onlineCount: 4,
            offlineCount: 3,
            isLoadingStatus: false
        )
    )
}

private func aggregatedStatsHeaderPreviewContent(viewModel: DeviceListViewModel) -> some View {
    ScrollView {
        DeviceGridSectionView(
            viewModel: viewModel,
            subscriptionAccessPolicy: PreviewFixtures.sampleSubscriptionAccessPolicy,
            showFleetWeeklyRecap: {},
            handleSelection: { _, _ in }
        )
    }
}

private func makeAggregatedStatsPreviewDefaults() -> UserDefaults {
    UserDefaults(suiteName: "preview.aggregated") ?? .standard
}

@MainActor
private func makeAggregatedStatsHeaderPreviewViewModel(
    onlineCount: Int,
    offlineCount: Int,
    isLoadingStatus: Bool
) -> DeviceListViewModel {
    UserDefaults.standard.set(true, forKey: "ai_enabled")

    let totalDeviceCount = onlineCount + offlineCount
    let devices = (1...totalDeviceCount).map { index in
        SavedDevice(
            name: "Preview Miner \(index)",
            ipAddress: "192.168.5.\(index)"
        )
    }
    let metricsByIP = Dictionary(
        uniqueKeysWithValues: devices.enumerated().map { offset, device in
            (
                device.ipAddress,
                DeviceMetrics(
                    hashrate: 2_200,
                    temperature: offset.isMultiple(of: 2) ? 45 : 60,
                    power: 48,
                    bestDifficulty: 1.2,
                    poolURL: "preview.pool",
                    hostname: device.name
                )
            )
        }
    )
    let defaults = makeAggregatedStatsPreviewDefaults()
    defaults.removePersistentDomain(forName: "preview.aggregated")
    let viewModel = DeviceListViewModel(
        defaults: defaults,
        dependencies: .init(
            deviceManagement: .init(
                checkDevice: { ip in
                    let metrics = metricsByIP[ip] ?? .placeholder
                    return DiscoveredDevice(
                        ip: ip,
                        name: metrics.hostname ?? "Preview Miner",
                        hashrate: metrics.hashrate,
                        temperature: metrics.temperature,
                        bestDiff: "\(metrics.bestDifficulty)",
                        power: metrics.power,
                        poolURL: metrics.poolURL,
                        blockHeight: metrics.blockHeight,
                        networkDifficulty: metrics.networkDifficulty
                    )
                },
                deleteDevice: { _ in },
                reorderDevices: { _ in }
            ),
            reloadWidget: {},
            autoRefreshOnLoad: false
        )
    )

    viewModel.savedDevices = devices
    viewModel.deviceMetrics = metricsByIP
    viewModel.reachableIPs = Set(devices.prefix(onlineCount).map(\.ipAddress))
    viewModel.totalHashRate = metricsByIP.values.reduce(0) { $0 + $1.hashrate }
    viewModel.totalPower = metricsByIP.values.reduce(0) { $0 + $1.power }
    viewModel.bestOverallDiff = metricsByIP.values.map(\.bestDifficulty).max() ?? 0
    viewModel.fleetAISummary = AISummaryFormatter.fleetSummary(from: Array(metricsByIP.values))

    #if DEBUG
        if !isLoadingStatus {
            viewModel.markAggregatedStatsRefreshCompletedForPreview()
        }
    #endif

    return viewModel
}
