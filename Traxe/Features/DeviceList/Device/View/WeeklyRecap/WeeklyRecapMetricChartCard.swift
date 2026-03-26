import Charts
import SwiftUI

struct WeeklyRecapMetricChartCard: View {
    let title: String
    let points: [WeeklyRecapPoint]
    let value: KeyPath<WeeklyRecapPoint, Double>
    let formatter: (Double) -> String
    let axisFormatter: (Double) -> String
    let unitLabel: String
    let xAxisDates: [Date]
    let enforceZeroBaseline: Bool

    var body: some View {
        let values = points.map { $0[keyPath: value] }
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        let average = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let latestPoint = points.last
        let latestValue = latestPoint?[keyPath: value]
        let yDomain = WeeklyRecapChartPresenter.chartYDomain(
            for: values,
            enforceZeroBaseline: enforceZeroBaseline
        )
        let xDomain = WeeklyRecapChartPresenter.chartXDomain(for: xAxisDates)

        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            HStack {
                metricPair(label: "Min", value: formatter(minimum))
                Spacer()
                metricPair(label: "Avg", value: formatter(average))
                Spacer()
                metricPair(label: "Max", value: formatter(maximum))
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

                if let latestPoint, let latestValue {
                    Text(
                        "Latest \(formatter(latestValue)) • \(latestPoint.date.formatted(.dateTime.weekday(.abbreviated)))"
                    )
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }

            Chart(points, id: \.date) { point in
                let yValue = point[keyPath: value]

                AreaMark(
                    x: .value("Day", point.date, unit: .day),
                    yStart: .value("Baseline", yDomain.lowerBound),
                    yEnd: .value("Value", yValue)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.traxeGold.opacity(0.2),
                            Color.traxeGold.opacity(0.03),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Value", yValue)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color.traxeGold)

                PointMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Value", yValue)
                )
                .symbolSize(30)
                .foregroundStyle(Color.traxeGold)

                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.traxeGold.opacity(0.45))

                if point.date == latestPoint?.date {
                    PointMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Value", yValue)
                    )
                    .symbolSize(50)
                    .annotation(
                        position: .top,
                        alignment: .trailing,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        Text(formatter(yValue))
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
                            Text(axisFormatter(raw))
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
