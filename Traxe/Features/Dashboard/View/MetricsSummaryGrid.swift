import Observation
import SwiftData
import SwiftUI

struct MetricsSummaryGrid: View {
    @Bindable var viewModel: DashboardViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            // Row 1
            MetricSummaryItem(
                label: "Hash Rate",
                value: viewModel.connectionState == .connected
                    ? viewModel.formattedHashRate : "Loading",
                unit: viewModel.connectionState == .connected
                    ? viewModel.formattedHashRateUnit : "GH/s",
                isLoading: viewModel.connectionState != .connected
            )

            MetricSummaryItem(
                label: "Uptime",
                value: viewModel.connectionState == .connected
                    ? formatUptime(viewModel.uptime).value : "Loading",
                unit: viewModel.connectionState == .connected
                    ? formatUptime(viewModel.uptime).unit : "",
                isLoading: viewModel.connectionState != .connected
            )

            MetricSummaryItem(
                label: "Shares",
                value: viewModel.connectionState == .connected
                    ? viewModel.formattedSharesAccepted : "Loading",
                unit: "",
                isLoading: viewModel.connectionState != .connected
            )

            // Row 2
            MetricSummaryItem(
                label: "Efficiency",
                value: viewModel.connectionState == .connected
                    ? viewModel.currentMetrics.efficiency
                        .formatted(.number.precision(.fractionLength(2)))
                    : "Loading",
                unit: "W/Th",
                isLoading: viewModel.connectionState != .connected
            )

            MetricSummaryItem(
                label: "Best Diff",
                value: viewModel.connectionState == .connected
                    ? viewModel.formattedBestDifficulty.value : "Loading",
                unit: viewModel.connectionState == .connected
                    ? viewModel.formattedBestDifficulty.unit : "M",
                isLoading: viewModel.connectionState != .connected
            )

            MetricSummaryItem(
                label: "Power",
                value: viewModel.connectionState == .connected
                    ? viewModel.currentMetrics.power
                        .formatted(.number.precision(.fractionLength(1)))
                    : "Loading",
                unit: "W",
                isLoading: viewModel.connectionState != .connected
            )

            // Row 3
            MetricSummaryItem(
                label: "Input",
                value: viewModel.connectionState == .connected
                    ? viewModel.currentMetrics.inputVoltage.formatted(fractionDigits: 1)
                    : "Loading",
                unit: "V",
                isLoading: viewModel.connectionState != .connected
            )

            MetricSummaryItem(
                label: "ASIC",
                value: viewModel.connectionState == .connected
                    ? viewModel.currentMetrics.asicVoltage.formatted(fractionDigits: 1) : "Loading",
                unit: "V",
                isLoading: viewModel.connectionState != .connected
            )

            MetricSummaryItem(
                label: "Temp",
                value: viewModel.connectionState == .connected
                    ? viewModel.currentMetrics.temperature
                        .formatted(.number.precision(.fractionLength(0)))
                    : "Loading",
                unit: "°C",
                isLoading: viewModel.connectionState != .connected
            )

            // Row 4
            MetricSummaryItem(
                label: "Fan",
                value: viewModel.connectionState == .connected
                    ? Double(viewModel.currentMetrics.fanSpeedPercent)
                        .formatted(.number.precision(.fractionLength(0)))
                    : "Loading",
                unit: "%",
                isLoading: viewModel.connectionState != .connected
            )

            MetricSummaryItem(
                label: "Frequency",
                value: viewModel.connectionState == .connected
                    ? viewModel.currentMetrics.frequency
                        .formatted(.number.precision(.fractionLength(0)))
                    : "Loading",
                unit: "MHz",
                isLoading: viewModel.connectionState != .connected
            )

            MetricSummaryItem(
                label: "Measured",
                value: viewModel.connectionState == .connected
                    ? viewModel.currentMetrics.measuredVoltage.formatted(fractionDigits: 1)
                    : "Loading",
                unit: "V",
                isLoading: viewModel.connectionState != .connected
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
                let match = regex.firstMatch(
                    in: first,
                    range: NSRange(first.startIndex..., in: first)
                )
            {

                if let numberRange = Range(match.range(at: 1), in: first),
                    let unitRange = Range(match.range(at: 2), in: first)
                {
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
    var isLoading: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .default))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .redacted(reason: isLoading ? .placeholder : [])

            Text(unit.isEmpty ? label.uppercased() : "\(label.uppercased()) (\(unit.uppercased()))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .redacted(reason: isLoading ? .placeholder : [])
        }
        .frame(maxWidth: .infinity)
        .frame(height: 70)
        .padding(.vertical, 8)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.secondary.opacity(0.3), lineWidth: 0.5)
        )
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = makeMetricsSummaryPreviewContainer(config: config)
    let previewViewModel = DashboardViewModel(modelContext: container.mainContext)

    return MetricsSummaryGrid(viewModel: previewViewModel)
}

private func makeMetricsSummaryPreviewContainer(config: ModelConfiguration) -> ModelContainer {
    do {
        return try ModelContainer(for: HistoricalDataPoint.self, configurations: config)
    } catch {
        fatalError("Failed to create metrics summary preview container: \(error)")
    }
}
