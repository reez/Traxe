import Foundation

struct MiningLuckSnapshot {
    let dailyBlockProbability: Double
    let expectedSecondsToBlock: TimeInterval
}

enum MiningLuckPresenter {
    private static let secondsPerDay: TimeInterval = 60 * 60 * 24
    private static let secondsPerYear: TimeInterval = 365.25 * secondsPerDay
    private static let hashesPerDifficulty: Double = 4_294_967_296

    static func makeSummarySentence(from metrics: DeviceMetrics) -> String? {
        guard let snapshot = makeSnapshot(from: metrics) else {
            return nil
        }

        let dailyChanceText = formatProbability(snapshot.dailyBlockProbability)
        let expectedTimeText = formatDuration(snapshot.expectedSecondsToBlock)
        let oddsText = "This miner's solo odds to hit a block are \(dailyChanceText) today"

        return "\(oddsText) (\(expectedTimeText) expected)."
    }

    static func makeSnapshot(from metrics: DeviceMetrics) -> MiningLuckSnapshot? {
        guard metrics.hashrate.isFinite, metrics.hashrate > 0,
            let networkDifficulty = metrics.networkDifficulty,
            networkDifficulty.isFinite,
            networkDifficulty > 0
        else {
            return nil
        }

        let hashrateHps = metrics.hashrate * 1_000_000_000
        let expectedHashes = networkDifficulty * hashesPerDifficulty
        let expectedSecondsToBlock = expectedHashes / hashrateHps
        let dailyBlockProbability = 1 - exp(-secondsPerDay / expectedSecondsToBlock)

        return MiningLuckSnapshot(
            dailyBlockProbability: dailyBlockProbability,
            expectedSecondsToBlock: expectedSecondsToBlock
        )
    }

    private static func formatProbability(_ probability: Double) -> String {
        guard probability > 0 else {
            return "--"
        }

        let oneIn = 1 / probability
        if oneIn < 2 {
            return probability.formatted(.percent.precision(.fractionLength(1)))
        }

        return "1 in \(formatCompact(oneIn))"
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else {
            return "--"
        }

        let years = seconds / secondsPerYear
        if years >= 1 {
            return "\(formatCompact(years)) yr"
        }

        let days = seconds / secondsPerDay
        if days >= 1 {
            return "\(formatCompact(days)) d"
        }

        let hours = seconds / (60 * 60)
        return "\(max(hours, 1).formatted(.number.precision(.fractionLength(0)))) hr"
    }

    private static func formatCompact(_ value: Double) -> String {
        let absValue = abs(value)
        let scaled: Double
        let suffix: String

        switch absValue {
        case 1_000_000_000...:
            scaled = value / 1_000_000_000
            suffix = "B"
        case 1_000_000...:
            scaled = value / 1_000_000
            suffix = "M"
        case 1_000...:
            scaled = value / 1_000
            suffix = "K"
        default:
            scaled = value
            suffix = ""
        }

        let formatted: String
        if abs(scaled) >= 100 || suffix.isEmpty {
            formatted = scaled.formatted(.number.precision(.fractionLength(0)))
        } else {
            formatted = scaled.formatted(.number.precision(.fractionLength(0...1)))
        }

        return "\(formatted)\(suffix)"
    }
}
