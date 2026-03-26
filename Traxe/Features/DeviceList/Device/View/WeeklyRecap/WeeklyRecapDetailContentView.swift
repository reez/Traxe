import SwiftUI

struct WeeklyRecapDetailContentView: View {
    let recap: WeeklyRecap
    let showDateRange: Bool

    var body: some View {
        let weekDates = recap.dailyPoints.map(\.date)
        let hashratePoints = recap.dailyPoints.filter { $0.sampleCount > 0 }
        let temperaturePoints = recap.dailyPoints.filter {
            $0.sampleCount > 0 && $0.averageTemperature > 0
        }
        let hasTemperatureData = !temperaturePoints.isEmpty

        if showDateRange {
            Text(WeeklyRecapChartPresenter.dateRangeText(for: recap))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            WeeklyRecapStatCard(
                title: "Average Hash Rate",
                value: WeeklyRecapChartPresenter.formattedHashrate(recap.averageHashrate),
                subtitle: "Across \(recap.sampleCount) samples"
            )
            WeeklyRecapStatCard(
                title: "Peak Hash Rate",
                value: WeeklyRecapChartPresenter.formattedHashrate(recap.peakHashrate),
                subtitle: "Highest point this week"
            )
            WeeklyRecapStatCard(
                title: "Average Temperature",
                value:
                    hasTemperatureData
                    ? "\(recap.averageTemperature.formatted(.number.precision(.fractionLength(0))))°C"
                    : "--",
                subtitle:
                    hasTemperatureData
                    ? "Range \(recap.minTemperature.formatted(.number.precision(.fractionLength(0))))°C - \(recap.maxTemperature.formatted(.number.precision(.fractionLength(0))))°C"
                    : "No valid temperature samples this week"
            )
            WeeklyRecapStatCard(
                title: "Active Days",
                value: "\(recap.activeDays)/7",
                subtitle: WeeklyRecapChartPresenter.trendSubtitle(from: recap.hashrateChangePercent)
            )
        }
        .padding(.horizontal)

        if hashratePoints.isEmpty {
            WeeklyRecapMessageCardView(
                title: "Daily Average Hash Rate",
                message: "No hashrate samples were recorded this week."
            )
        } else {
            WeeklyRecapHashrateRangeChartCard(
                points: hashratePoints,
                xAxisDates: weekDates
            )
        }

        if hasTemperatureData {
            WeeklyRecapMetricChartCard(
                title: "Daily Average Temperature",
                points: temperaturePoints,
                value: \.averageTemperature,
                formatter: { value in
                    "\(value.formatted(.number.precision(.fractionLength(0))))°C"
                },
                axisFormatter: { value in
                    value.formatted(.number.precision(.fractionLength(0)))
                },
                unitLabel: "°C",
                xAxisDates: weekDates,
                enforceZeroBaseline: false
            )
        } else {
            WeeklyRecapMessageCardView(
                title: "Daily Average Temperature",
                message: "No valid temperature samples were recorded this week."
            )
        }
    }
}
