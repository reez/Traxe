import Foundation

// MARK: - AI Summary Model (Fleet Only)
struct AISummary: Identifiable, Codable {
    let id: UUID
    let content: String

    init(id: UUID = UUID(), content: String) {
        self.id = id
        self.content = content
    }
}

// MARK: - Shared AI Summary Formatter

enum AISummaryFormatter {
    static func fleetSummary(
        from metricsByIP: [String: DeviceMetrics],
        snapshot: FleetMetricSnapshot
    ) -> AISummary {
        guard let totalHashrate = snapshot.totalHashrate else {
            return AISummary(content: snapshot.statusText + ".")
        }
        let (value, unit) = totalHashrate.formattedHashRateWithUnit()
        var content = "\(snapshot.statusText). Total hash rate \(value) \(unit)"
        let metrics = snapshot.includedDeviceIDs.compactMap { metricsByIP[$0] }
        let temperatures = metrics.filter { $0.isTemperatureKnown }.map(\.temperature)
            .filter { $0.isFinite && $0 > 0 }
        if let minimum = temperatures.min(), let maximum = temperatures.max() {
            let minimumText = minimum.formatted(.number.precision(.fractionLength(0)))
            let maximumText = maximum.formatted(.number.precision(.fractionLength(0)))
            if minimumText == maximumText {
                content += ", temperature \(minimumText)°C"
            } else {
                content += ", temperatures \(minimumText)–\(maximumText)°C"
            }
        }
        let hotDevices = temperatures.filter { $0 > AppConstants.AI.hotTemperatureThreshold }.count
        if hotDevices > 0 { content += " (\(hotDevices) above 75°C)" }
        if let power = snapshot.totalPower {
            content += ", and \(power.formatted(.number.precision(.fractionLength(0))))W of power"
        }
        return AISummary(content: content + ".")
    }

    static func fleetSummary(from metrics: [DeviceMetrics]) -> AISummary? {
        guard !metrics.isEmpty else { return nil }

        let totalHash = metrics.reduce(0) { $0 + $1.hashrate }
        let (hashValue, hashUnit) = totalHash.formattedHashRateWithUnit()
        let temps = metrics.filter { $0.isTemperatureKnown }.map(\.temperature)
        let nonZeroTemps = temps.filter { $0.isFinite && $0 > 0 }
        let totalPower = metrics.reduce(0) { $0 + $1.power }
        let hotDevices = metrics.filter {
            $0.isTemperatureKnown && $0.temperature.isFinite
                && $0.temperature > AppConstants.AI.hotTemperatureThreshold
        }
        .count
        let deviceCount = metrics.count

        var content = "\(deviceCount) miners with a total of \(hashValue) \(hashUnit), "
        if nonZeroTemps.isEmpty {
            content += "temperature unavailable"
        } else {
            let minTemp = nonZeroTemps.min() ?? 0
            let maxTemp = nonZeroTemps.max() ?? 0
            let minimumText = minTemp.rounded(.towardZero).formatted(
                .number.precision(.fractionLength(0))
            )
            let maximumText = maxTemp.rounded(.towardZero).formatted(
                .number.precision(.fractionLength(0))
            )
            if minimumText == maximumText {
                content += "temperature \(minimumText)°C"
            } else {
                content += "a temp range of \(minimumText)-\(maximumText)°C"
            }
        }
        if hotDevices > 0 { content += " (\(hotDevices) above 75°C)" }
        content += ", and \(totalPower.formatted(.number.precision(.fractionLength(0))))W of power."

        return AISummary(content: content)
    }

}
