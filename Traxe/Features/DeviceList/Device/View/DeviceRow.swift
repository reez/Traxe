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
