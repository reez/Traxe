import SwiftData
import SwiftUI

struct MetricsSummaryGrid: View {
    @ObservedObject var viewModel: DashboardViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            // Row 1
            MetricSummaryItem(
                label: "Hash Rate",
                value: viewModel.connectionState == .connected
                    ? viewModel.formattedHashRate : "---",
                unit: viewModel.connectionState == .connected
                    ? viewModel.formattedHashRateUnit : "GH/s"
            )

            MetricSummaryItem(
                label: "Uptime",
                value: viewModel.connectionState == .connected
                    ? formatUptime(viewModel.uptime).value : "---",
                unit: viewModel.connectionState == .connected
                    ? formatUptime(viewModel.uptime).unit : ""
            )

            MetricSummaryItem(
                label: "Shares",
                value: viewModel.connectionState == .connected
                    ? viewModel.formattedSharesAccepted : "---",
                unit: ""
            )

            // Row 2
            MetricSummaryItem(
                label: "Efficiency",
                value: viewModel.connectionState == .connected
                    ? String(format: "%.2f", viewModel.currentMetrics.efficiency) : "---",
                unit: "W/Th"
            )

            MetricSummaryItem(
                label: "Best Diff",
                value: viewModel.connectionState == .connected
                    ? viewModel.formattedBestDifficulty.value : "---",
                unit: viewModel.connectionState == .connected
                    ? viewModel.formattedBestDifficulty.unit : "M"
            )

            MetricSummaryItem(
                label: "Power",
                value: viewModel.connectionState == .connected
                    ? String(format: "%.1f", viewModel.currentMetrics.power) : "---",
                unit: "W"
            )

            // Row 3
            MetricSummaryItem(
                label: "Input",
                value: viewModel.connectionState == .connected
                    ? String(format: "%.1f", viewModel.currentMetrics.inputVoltage) : "---",
                unit: "V"
            )

            MetricSummaryItem(
                label: "ASIC",
                value: viewModel.connectionState == .connected
                    ? String(format: "%.1f", viewModel.currentMetrics.asicVoltage) : "---",
                unit: "V"
            )

            MetricSummaryItem(
                label: "Temp",
                value: viewModel.connectionState == .connected
                    ? String(format: "%.0f", viewModel.currentMetrics.temperature) : "---",
                unit: "°C"
            )

            // Row 4
            MetricSummaryItem(
                label: "Fan",
                value: viewModel.connectionState == .connected
                    ? String(format: "%.0f", Double(viewModel.currentMetrics.fanSpeedPercent))
                    : "---",
                unit: "%"
            )

            MetricSummaryItem(
                label: "Frequency",
                value: viewModel.connectionState == .connected
                    ? String(format: "%.0f", viewModel.currentMetrics.frequency) : "---",
                unit: "MHz"
            )

            MetricSummaryItem(
                label: "Measured",
                value: viewModel.connectionState == .connected
                    ? String(format: "%.1f", viewModel.currentMetrics.measuredVoltage) : "---",
                unit: "V"
            )
        }
        .padding()
    }

    private func formatUptime(_ uptime: String) -> (value: String, unit: String) {
        // The uptime string comes in format like "20m", "22h 39m", "9d 45m"
        // We want to extract the first component and split number from unit
        let components = uptime.components(separatedBy: " ")
        if let first = components.first, !first.isEmpty {
            // Use regex to split number and unit more reliably
            let pattern = "^(\\d+)([a-zA-Z]+)$"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: first, range: NSRange(first.startIndex..., in: first)) {
                
                if let numberRange = Range(match.range(at: 1), in: first),
                   let unitRange = Range(match.range(at: 2), in: first) {
                    let number = String(first[numberRange])
                    let unit = String(first[unitRange]).uppercased()
                    return (value: number, unit: unit)
                }
            }
        }
        // Fallback - return the whole string with no unit
        return (value: uptime, unit: "")
    }
}

struct MetricSummaryItem: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .default))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(unit.isEmpty ? label.uppercased() : "\(label.uppercased()) (\(unit.uppercased()))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 70)
        .padding(.vertical, 8)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: HistoricalDataPoint.self, configurations: config)
    let previewViewModel = DashboardViewModel(modelContext: container.mainContext)

    return MetricsSummaryGrid(viewModel: previewViewModel)
}
