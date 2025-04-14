import SwiftUI

struct DeviceRow: View {
    let device: SavedDevice
    var isAccessible: Bool = true
    var deviceMetrics: DeviceMetrics?

    private var displayHashRateString: String {
        if let metrics = deviceMetrics {
            let valueToDisplay =
                metrics.hashrate >= 1000 ? metrics.hashrate / 1000 : metrics.hashrate
            return String(format: "%.1f", valueToDisplay)
        } else {
            return "---"
        }
    }

    private var displayHashRateUnit: String {
        if let metrics = deviceMetrics {
            return metrics.hashrate >= 1000 ? "TH/s" : "GH/s"
        } else {
            return "GH/s"
        }
    }

    private var formattedBestDifficulty: (value: String, unit: String) {
        guard let metrics = deviceMetrics else { return ("---", "M") }
        return metrics.bestDifficulty.formattedDifficulty()
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .center, spacing: 10) {
                if !isAccessible {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                VStack(spacing: 0) {
                    Text(displayHashRateString)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                        .contentTransition(.numericText())
                        .animation(.default, value: displayHashRateString)
                        .redacted(reason: deviceMetrics == nil ? .placeholder : [])

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("Hash Rate".uppercased())
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)

                        Text("(\(displayHashRateUnit))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                }
                if deviceMetrics != nil {
                    HStack(alignment: .center, spacing: 4) {
                        HStack(spacing: 2) {
                            Text(formattedBestDifficulty.value)
                            Text(formattedBestDifficulty.unit)
                        }
                        Text("Best Difficulty".uppercased())
                    }
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }

                if let metrics = deviceMetrics, let poolURL = metrics.poolURL, !poolURL.isEmpty {
                    Text(poolURL)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }

                Text(deviceMetrics?.hostname ?? device.name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                
                Text(device.ipAddress)
                    .font(.caption)
                    .foregroundStyle(Color.traxeGold)

                HStack {
                    Text("Details")
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                }
                .font(.caption)
                .foregroundStyle(.primary)

            }
            .padding()
            .frame(maxWidth: .infinity)
            Spacer()
        }
    }
}

#Preview("Accessible") {
    DeviceRow(device: SavedDevice.init(name: "device", ipAddress: "1.1.1.1"), isAccessible: true)
}

#Preview("Not Accessible") {
    DeviceRow(device: SavedDevice.init(name: "device", ipAddress: "1.1.1.1"), isAccessible: false)
}
