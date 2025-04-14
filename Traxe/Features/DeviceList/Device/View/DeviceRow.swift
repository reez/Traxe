import SwiftUI

struct DeviceRow: View {
    let device: SavedDevice
    var isAccessible: Bool = true
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

    private var formattedBestDifficulty: (value: String, unit: String) {
        guard let metrics = deviceMetrics else { return ("---", "M") }
        let valueM = metrics.bestDifficulty
        if valueM == 0 { return ("0", "M") }
        let tera = 1_000_000.0
        let giga = 1_000.0
        let kilo = 0.001
        var displayValue: Double
        var unit: String
        if abs(valueM) >= tera {
            displayValue = valueM / tera
            unit = "T"
        } else if abs(valueM) >= giga {
            displayValue = valueM / giga
            unit = "G"
        } else if abs(valueM) >= 1.0 {
            displayValue = valueM
            unit = "M"
        } else if abs(valueM) >= kilo {
            displayValue = valueM / kilo
            unit = "K"
        } else {
            displayValue = valueM
            unit = "M"
        }
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        if unit == "T" || unit == "G" {
            numberFormatter.maximumFractionDigits = 2
        } else if unit == "M" {
            if abs(valueM) >= 1.0 || valueM == 0 {
                numberFormatter.maximumFractionDigits = 1
                if displayValue.truncatingRemainder(dividingBy: 1) == 0 {
                    numberFormatter.maximumFractionDigits = 0
                }
            } else {
                numberFormatter.maximumFractionDigits = 3
            }
        } else {
            numberFormatter.maximumFractionDigits = 0
        }
        numberFormatter.minimumFractionDigits = 0
        let formattedValueString =
            numberFormatter.string(from: NSNumber(value: displayValue)) ?? "\(displayValue)"
        return (value: formattedValueString, unit: unit)
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

                if deviceMetrics != nil {
                    HStack(alignment: .center, spacing: 4) {
                        Image(systemName: "star")
                            .font(.caption2)
                        Text(formattedBestDifficulty.value)
                        Text(formattedBestDifficulty.unit)
                            .font(.caption2)
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

                if isAccessible {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical)
        .task {
            do {
                let discoveredDevice = try await DeviceManagementService.checkDevice(
                    ip: device.ipAddress
                )
                let bestDiffString = discoveredDevice.bestDiff.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                let multipliers: [Character: Double] = [
                    "K": 1_000,
                    "M": 1_000_000,
                    "G": 1_000_000_000,
                    "T": 1_000_000_000_000,
                    "P": 1_000_000_000_000_000,
                ]
                var rawBestDiffValue: Double = 0.0
                if !bestDiffString.isEmpty {
                    let lastChar = bestDiffString.last!
                    var numericPartString = bestDiffString
                    var multiplier: Double = 1.0
                    if let mult = multipliers[lastChar.uppercased().first!] {
                        multiplier = mult
                        numericPartString = String(bestDiffString.dropLast())
                    } else if lastChar.isLetter {
                        multiplier = 1.0
                        numericPartString = String(bestDiffString.dropLast())
                    }
                    if let numericValue = Double(numericPartString) {
                        rawBestDiffValue = numericValue * multiplier / 1_000_000.0  // always store in M
                    }
                }
                deviceMetrics = DeviceMetrics(
                    hashrate: discoveredDevice.hashrate,
                    temperature: discoveredDevice.temperature,
                    bestDifficulty: rawBestDiffValue,
                    poolURL: discoveredDevice.poolURL
                )
            } catch {}
        }
    }
}

#Preview("Accessible") {
    DeviceRow(device: SavedDevice.init(name: "device", ipAddress: "1.1.1.1"), isAccessible: true)
}

#Preview("Not Accessible") {
    DeviceRow(device: SavedDevice.init(name: "device", ipAddress: "1.1.1.1"), isAccessible: false)
}
