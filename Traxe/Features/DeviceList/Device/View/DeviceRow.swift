import SwiftUI

struct DeviceRow: View {
    let device: SavedDevice
    @State private var deviceMetrics: DeviceMetrics?

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

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                    Text("Hash Rate").bold()
                    Spacer()
                }
                .foregroundStyle(.primary)
                .font(.subheadline)

                HStack(alignment: .firstTextBaseline) {
                    Text(displayHashRateString)
                        .font(.title)
                        .fontWeight(.semibold)
                        .contentTransition(.numericText())
                        .animation(.default, value: displayHashRateString)
                        .redacted(reason: deviceMetrics == nil ? .placeholder : [])

                    Text(displayHashRateUnit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let metrics = deviceMetrics, let poolURL = metrics.poolURL, !poolURL.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text(poolURL)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }

            HStack(alignment: .center, spacing: 20) {
                Text(device.ipAddress)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.secondary.opacity(0.2)))
                    .foregroundStyle(Color.traxeGold)

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical)
        .task {
            do {
                let discoveredDevice = try await DeviceManagementService.checkDevice(
                    ip: device.ipAddress
                )
                deviceMetrics = DeviceMetrics(
                    hashrate: discoveredDevice.hashrate,
                    temperature: discoveredDevice.temperature,
                    poolURL: discoveredDevice.poolURL
                )
            } catch {}
        }
    }
}
