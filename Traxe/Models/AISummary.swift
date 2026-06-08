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
    static func fleetSummary(from metrics: [DeviceMetrics]) -> AISummary? {
        guard !metrics.isEmpty else { return nil }

        let totalHash = metrics.reduce(0) { $0 + $1.hashrate }
        let (hashValue, hashUnit) = totalHash.formattedHashRateWithUnit()
        let temps = metrics.map { $0.temperature }
        let nonZeroTemps = temps.filter { $0 > 0 }
        let totalPower = metrics.reduce(0) { $0 + $1.power }
        let hotDevices = metrics.filter { $0.temperature > AppConstants.AI.hotTemperatureThreshold }
            .count
        let deviceCount = metrics.count

        var content = "\(deviceCount) miners with a total of \(hashValue) \(hashUnit), "
        if nonZeroTemps.isEmpty {
            content += "temperatures 0°C"
        } else {
            let minTemp = nonZeroTemps.min() ?? 0
            let maxTemp = nonZeroTemps.max() ?? 0
            content += "a temp range of \(Int(minTemp))-\(Int(maxTemp))°C"
        }
        if hotDevices > 0 { content += " (\(hotDevices) above 75°C)" }
        content += ", and \(totalPower.formatted(.number.precision(.fractionLength(0))))W of power."

        return AISummary(content: content)
    }

}
