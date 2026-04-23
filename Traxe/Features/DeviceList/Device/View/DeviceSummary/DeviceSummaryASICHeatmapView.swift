import SwiftUI

struct DeviceSummaryASICHeatmapView: View {
    let monitors: [ASICHashrateMonitor]
    let expectedHashrate: Double
    let chipTemperature: Double
    let isChipTemperatureKnown: Bool
    let vrTemperature: Double
    let isVRTemperatureKnown: Bool
    let errorPercentage: Double?

    private var asicCount: Int {
        max(monitors.count, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hashrate Registers")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 14) {
                ForEach(monitors, id: \.index) { monitor in
                    VStack(alignment: .leading, spacing: 8) {
                        if monitors.count > 1 {
                            Text("ASIC \(monitor.index)")
                                .font(.subheadline.weight(.semibold))
                        }

                        Text("Domains")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(monitor.domains.indices, id: \.self) { index in
                                let value = monitor.domains[index]
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(domainFillColor(value, monitor: monitor))
                                        .frame(width: 14, height: 14)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    domainBorderColor(monitor: monitor),
                                                    lineWidth: 1.5
                                                )
                                        )

                                    Text(formattedDomain(value))
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .foregroundStyle(.primary)
                                }
                                .accessibilityLabel("Domain \(index + 1), \(formattedDomain(value))")
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func domainFillColor(_ value: Double, monitor: ASICHashrateMonitor) -> Color {
        guard value > 0 else {
            return .clear
        }

        let expectedDomainHashrate = expectedDomainHashrate(for: monitor)
        guard expectedDomainHashrate > 0 else {
            return .secondary.opacity(0.35)
        }

        let ratio = min(max(value / expectedDomainHashrate, 0.0), 1.0)
        return .traxeGold.opacity(ratio)
    }

    private func domainBorderColor(monitor: ASICHashrateMonitor) -> Color {
        let expectedDomainHashrate = expectedDomainHashrate(for: monitor)
        guard expectedDomainHashrate > 0 else {
            return .secondary.opacity(0.5)
        }

        return .traxeGold
    }

    private func expectedDomainHashrate(for monitor: ASICHashrateMonitor) -> Double {
        guard expectedHashrate > 0 else {
            return 0.0
        }

        let domainCount = max(monitor.domains.count, 1)
        return expectedHashrate / Double(asicCount * domainCount)
    }

    private func formattedDomain(_ value: Double) -> String {
        guard value > 0 else {
            return "0 H/s"
        }

        let formatted = value.formattedHashRateWithUnit()
        return "\(formatted.value) \(formatted.unit)"
    }
}

#Preview("Hashrate Registers - Normal") {
    DeviceSummaryASICHeatmapView(
        monitors: [
            ASICHashrateMonitor(
                index: 1,
                total: 325.6,
                domains: [0, 50.1, 100.2, 175.3]
            )
        ],
        expectedHashrate: 721.0,
        chipTemperature: 53,
        isChipTemperatureKnown: true,
        vrTemperature: 62,
        isVRTemperatureKnown: true,
        errorPercentage: nil
    )
    .padding()
}

#Preview("Hashrate Registers - Multiple ASICs") {
    DeviceSummaryASICHeatmapView(
        monitors: [
            ASICHashrateMonitor(
                index: 1,
                total: 620,
                domains: [92, 88, 94, 77, 91, 86, 95, 82, 90, 79, 93, 87]
            ),
            ASICHashrateMonitor(
                index: 2,
                total: 590,
                domains: [80, 72, 75, 78, 69, 81, 77, 74, 83, 70, 76, 79]
            ),
        ],
        expectedHashrate: 2_000,
        chipTemperature: 67,
        isChipTemperatureKnown: true,
        vrTemperature: 54,
        isVRTemperatureKnown: true,
        errorPercentage: 1.42
    )
    .padding()
}

#Preview("Hashrate Registers - Zero Domain") {
    DeviceSummaryASICHeatmapView(
        monitors: [
            ASICHashrateMonitor(
                index: 1,
                total: 709,
                domains: [219, 0, 236, 254]
            )
        ],
        expectedHashrate: 960,
        chipTemperature: 53,
        isChipTemperatureKnown: true,
        vrTemperature: 62,
        isVRTemperatureKnown: true,
        errorPercentage: nil
    )
    .padding()
}

#Preview("Hashrate Registers - Weak Domain") {
    DeviceSummaryASICHeatmapView(
        monitors: [
            ASICHashrateMonitor(
                index: 1,
                total: 744.859,
                domains: [241, 0.859, 238, 265]
            )
        ],
        expectedHashrate: 960,
        chipTemperature: 53,
        isChipTemperatureKnown: true,
        vrTemperature: 62,
        isVRTemperatureKnown: true,
        errorPercentage: 1.42
    )
    .padding()
}
