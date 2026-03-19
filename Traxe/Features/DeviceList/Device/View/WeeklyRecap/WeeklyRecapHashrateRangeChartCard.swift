import Charts
import SwiftUI

struct WeeklyRecapHashrateRangeChartCard: View {
    let points: [WeeklyRecapPoint]
    let xAxisDates: [Date]

    var body: some View {
        let minHashrate = points.map(\.minHashrate).min() ?? 0
        let maxHashrate = points.map(\.maxHashrate).max() ?? 0
        let averageHashrate =
            points.isEmpty ? 0 : points.map(\.averageHashrate).reduce(0, +) / Double(points.count)
        let latestPoint = points.last
        let rangeValues = points.flatMap { [$0.minHashrate, $0.maxHashrate] }
        let yDomain = WeeklyRecapChartPresenter.chartYDomain(
            for: rangeValues,
            enforceZeroBaseline: true
        )
        let unitLabel = WeeklyRecapChartPresenter.hashrateUnitLabel(for: points.map(\.maxHashrate))
        let xDomain = WeeklyRecapChartPresenter.chartXDomain(for: xAxisDates)

        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Hash Rate Range")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack {
                metricPair(
                    label: "Min",
                    value: WeeklyRecapChartPresenter.formattedHashrate(minHashrate)
                )
                Spacer()
                metricPair(
                    label: "Avg",
                    value: WeeklyRecapChartPresenter.formattedHashrate(averageHashrate)
                )
                Spacer()
                metricPair(
                    label: "Max",
                    value: WeeklyRecapChartPresenter.formattedHashrate(maxHashrate)
                )
            }

            HStack(alignment: .center) {
                Text(unitLabel)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Color.primary.opacity(0.07),
                        in: Capsule(style: .continuous)
                    )

                Spacer()

                if let latestPoint {
                    Text(
                        "Latest \(WeeklyRecapChartPresenter.formattedHashrate(latestPoint.averageHashrate)) • \(latestPoint.date.formatted(.dateTime.weekday(.abbreviated)))"
                    )
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }

            Chart(points, id: \.date) { point in
                AreaMark(
                    x: .value("Day", point.date, unit: .day),
                    yStart: .value("Min", point.minHashrate),
                    yEnd: .value("Max", point.maxHashrate)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.traxeGold.opacity(0.22),
                            Color.traxeGold.opacity(0.04),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Average", point.averageHashrate)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color.traxeGold)

                PointMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Average", point.averageHashrate)
                )
                .symbolSize(28)
                .foregroundStyle(Color.traxeGold)

                RuleMark(y: .value("Average", averageHashrate))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.traxeGold.opacity(0.45))

                if point.date == latestPoint?.date {
                    PointMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Average", point.averageHashrate)
                    )
                    .symbolSize(50)
                    .annotation(
                        position: .top,
                        alignment: .trailing,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        Text(WeeklyRecapChartPresenter.formattedHashrate(point.averageHashrate))
                            .font(.caption2)
                            .monospacedDigit()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Color(uiColor: .secondarySystemBackground),
                                in: Capsule(style: .continuous)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                            )
                            .foregroundStyle(.primary)
                            .offset(x: -34)
                    }
                }
            }
            .frame(height: 200)
            .chartXScale(domain: xDomain)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: xAxisDates) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    AxisTick()
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.primary.opacity(0.08))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisTick()
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                        .foregroundStyle(Color.primary.opacity(0.12))
                    AxisValueLabel {
                        if let raw = value.as(Double.self) {
                            Text(raw.formattedHashRateWithUnit().value)
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .background(Color.primary.opacity(0.025))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .padding(.horizontal)
    }

    private func metricPair(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
    }
}
