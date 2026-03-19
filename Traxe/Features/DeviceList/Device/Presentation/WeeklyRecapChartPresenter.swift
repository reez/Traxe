import Foundation

enum WeeklyRecapChartPresenter {
    static func dateRangeText(for recap: WeeklyRecap) -> String {
        "\(shortDate(recap.startDate)) - \(shortDate(recap.endDate))"
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func formattedHashrate(_ value: Double) -> String {
        let formatted = value.formattedHashRateWithUnit()
        return "\(formatted.value) \(formatted.unit)"
    }

    static func hashrateUnitLabel(for values: [Double]) -> String {
        let reference = values.max() ?? 0
        return reference.formattedHashRateWithUnit().unit
    }

    static func chartYDomain(
        for values: [Double],
        enforceZeroBaseline: Bool
    ) -> ClosedRange<Double> {
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }

        if minimum == maximum {
            let padding = max(abs(maximum) * 0.1, 1)
            let lower = enforceZeroBaseline ? 0 : minimum - padding
            return lower...(maximum + padding)
        }

        let span = maximum - minimum
        let padding = max(span * 0.18, 1)
        let lower = enforceZeroBaseline ? 0 : minimum - padding
        let upper = maximum + padding
        return lower...upper
    }

    static func chartXDomain(for dates: [Date]) -> ClosedRange<Date> {
        guard let start = dates.first, let end = dates.last else {
            let now = Date()
            return now...now
        }

        let rightEdgePadding: TimeInterval = 36 * 60 * 60
        return start...end.addingTimeInterval(rightEdgePadding)
    }

    static func trendSubtitle(from percent: Double?) -> String {
        guard let percent else { return "Need more data for trend" }
        if percent == 0 {
            return "Flat week-over-week trend"
        }
        let direction = percent > 0 ? "up" : "down"
        let magnitude = abs(percent).formatted(.number.precision(.fractionLength(1)))
        return "\(magnitude)% \(direction) from first active day"
    }

    static func formattedPoolPercent(_ percent: Double) -> String {
        let precision: FloatingPointFormatStyle<Double>.Configuration.Precision =
            percent == percent.rounded()
            ? .fractionLength(0)
            : .fractionLength(1)
        return percent.formatted(.number.precision(precision))
    }

    static func formattedBlockHeight(_ blockHeight: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: blockHeight)) ?? "\(blockHeight)"
    }
}
