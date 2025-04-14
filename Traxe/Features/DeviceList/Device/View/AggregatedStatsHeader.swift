import SwiftUI

struct AggregatedStatsHeader: View {
    @ObservedObject var viewModel: DeviceListViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            StatItem(
                label: "Hash Rate",
                value: viewModel.totalHashRate,
                unit: "TH/s",
                isLoading: viewModel.isLoadingAggregatedStats || viewModel.totalHashRate == 0.0,
                name: "bolt.fill",
                onRefresh: {
                    await viewModel.updateAggregatedStats()
                }
            )

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 0, alignment: .leading),
                    count: 3
                ),
                alignment: .leading,
                spacing: 40
            ) {
                ForEach(Array(viewModel.savedDevices.prefix(9).enumerated()), id: \.element.id) {
                    index,
                    device in
                    let metrics = viewModel.deviceMetrics[device.ipAddress]
                    let hashRate = metrics?.hashrate ?? 0.0
                    let displayValue = hashRate >= 1000 ? hashRate / 1000 : hashRate
                    let unit = hashRate >= 1000 ? "TH/S" : "GH/S"

                    VStack(alignment: .leading, spacing: 1) {
                        Text(metrics != nil ? String(format: "%.1f", displayValue) : "---")
                            .font(.system(size: 32, weight: .semibold))
                            .fontDesign(.rounded)
                            .redacted(
                                reason: viewModel.isLoadingAggregatedStats || metrics == nil
                                    ? .placeholder : []
                            )

                        Text("\(unit)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
    }
}

#Preview {
    let mockDefaults = UserDefaults(suiteName: "preview.aggregated")!
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

    return AggregatedStatsHeader(viewModel: viewModel)
}
