import Foundation
import SwiftUI

#if canImport(FoundationModels)
    import FoundationModels

    /// Structured output keeps the model from drifting into preambles — the schema
    /// only has room for the summary text itself.
    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    private struct MinerSummaryOutput {
        @Guide(description: "The summary sentence(s) only. No introductory phrases.")
        var summary: String
    }
#endif

@available(iOS 18.0, macOS 15.0, *)
actor AIAnalysisService {

    private static let summaryInstructions = """
        You are a technical analyst. Write concise miner summaries.

        CRITICAL: Only output the summary text. NO introductory phrases.

        Be natural and conversational while including all technical details.
        """
    private let networkService: NetworkService
    private var languageSession: Any?  // Type-erased to avoid availability issues
    private var lastGenerationFailed: Bool = false
    private var lastErrorMessage: String? = nil

    init(networkService: NetworkService = NetworkService()) {
        self.networkService = networkService
        Task {
            await setupFoundationModels()
        }
    }

    private func setupFoundationModels() async {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *), AIFeatureFlags.foundationModelsAvailable,
                AIFeatureFlags.isEnabledByUser
            {
                // Check system availability FIRST before creating session
                let availability = SystemLanguageModel.default.availability

                switch availability {
                case .available:
                    languageSession = LanguageModelSession(
                        instructions: Self.summaryInstructions
                    )
                    lastGenerationFailed = false
                    lastErrorMessage = nil
                case .unavailable(let reason):
                    if setupPrivateCloudComputeFallback() {
                        return
                    }
                    languageSession = nil
                    lastGenerationFailed = true
                    lastErrorMessage =
                        switch reason {
                        case .deviceNotEligible:
                            "Miner not compatible"
                        case .appleIntelligenceNotEnabled:
                            "Apple Intelligence not enabled"
                        case .modelNotReady:
                            "Model is downloading"
                        @unknown default:
                            "Model unavailable"
                        }
                @unknown default:
                    if setupPrivateCloudComputeFallback() {
                        return
                    }
                    languageSession = nil
                    lastGenerationFailed = true
                    lastErrorMessage = "Unknown availability status"
                }
            }
        #endif
    }

    /// iOS 27 can run the same session against Private Cloud Compute when the
    /// on-device model can't (older device, Apple Intelligence off). Free under
    /// the Small Business Program quota; unavailable falls through to heuristics.
    /// Returns true when a cloud-backed session was installed.
    private func setupPrivateCloudComputeFallback() -> Bool {
        #if canImport(FoundationModels) && compiler(>=6.4)
            if #available(iOS 27.0, macOS 27.0, *) {
                let cloudModel = PrivateCloudComputeLanguageModel()
                guard cloudModel.isAvailable else { return false }
                languageSession = LanguageModelSession(
                    model: cloudModel,
                    instructions: Self.summaryInstructions
                )
                lastGenerationFailed = false
                lastErrorMessage = nil
                return true
            }
        #endif
        return false
    }

    func refreshFoundationModelsSetup() async {
        await setupFoundationModels()
    }

    // MARK: - AI Summary Generation

    func generateFleetSummary(forDevices deviceIPs: [String]) async throws -> AISummary {

        var allMetrics: [DeviceMetrics] = []
        var deviceCount = 0

        try await withThrowingTaskGroup(of: DeviceMetrics?.self) { group in
            for ipAddress in deviceIPs {
                group.addTask { [self] in
                    do {
                        let telemetry = try await networkService.fetchMinerTelemetry(
                            ipAddressOverride: ipAddress
                        )
                        return DeviceMetrics(from: telemetry)
                    } catch {
                        return nil
                    }
                }
            }

            for try await metrics in group {
                if let metrics = metrics {
                    allMetrics.append(metrics)
                    deviceCount += 1
                }
            }
        }

        guard deviceCount > 0 else {
            throw NSError(
                domain: "AIAnalysisService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No miners available for fleet analysis"]
            )
        }

        // Try Foundation Models first if available

        #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *), AIFeatureFlags.useFoundationModels,
                let session = languageSession as? LanguageModelSession
            {
                do {
                    let basicSummary = AISummaryFormatter.fleetSummary(from: allMetrics)
                    let variation = try await generateFleetSummaryVariation(
                        using: session,
                        basicData: basicSummary?.content ?? ""
                    )
                    lastGenerationFailed = false
                    lastErrorMessage = nil
                    return AISummary(content: variation)
                } catch {
                    lastGenerationFailed = true
                    lastErrorMessage = "Generation failed"
                    // Fall back to basic formatter
                }
            }
        #endif

        // Fallback to basic summary formatter
        if let formatted = AISummaryFormatter.fleetSummary(from: allMetrics) {
            return formatted
        }
        throw NSError(
            domain: "AIAnalysisService",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Unable to generate fleet summary"]
        )
    }

    func generateDeviceSummary(
        forDevice deviceIP: String,
        withHistoricalData historicalData: [HistoricalDataPoint] = []
    ) async throws -> AISummary {

        let telemetry = try await networkService.fetchMinerTelemetry(ipAddressOverride: deviceIP)
        let metrics = DeviceMetrics(from: telemetry)

        let hashRate = metrics.hashrate
        let temperature = telemetry.temperature
        let power = telemetry.power
        let fanSpeedPercent = metrics.fanSpeedPercent
        let miningLuckSentence = MiningLuckPresenter.makeSummarySentence(from: metrics)

        let hashRateFormatted = hashRate.formattedHashRateWithUnit()
        var summary: String

        if !historicalData.isEmpty {
            let historicalTrend = analyzeHistoricalTrend(
                historicalData: historicalData
            )
            if !historicalTrend.isEmpty {
                // Recorded facts must not pass through a free-form model rewrite.
                return AISummary(
                    content: appendingMiningLuckSentence(
                        miningLuckSentence,
                        to: historicalTrend
                    )
                )
            } else {
                // Fall back to current stats if trend is empty
                summary =
                    "Your miner is producing \(hashRateFormatted.value) \(hashRateFormatted.unit)."
            }
        } else {
            // No historical data; show current stats
            summary =
                metrics.isHashrateKnown
                ? "Your miner is producing \(hashRateFormatted.value) \(hashRateFormatted.unit)"
                : "Your miner’s hash rate is unavailable"

            if let temperature, temperature.isFinite {
                if temperature > AppConstants.AI.hotTemperatureThreshold {
                    summary +=
                        ", running warm at \(temperature.rounded(.towardZero).formatted(.number.precision(.fractionLength(0))))°C with fan at \(fanSpeedPercent)%"
                    if fanSpeedPercent < AppConstants.AI.lowFanSpeedThreshold {
                        summary += " - consider improving ventilation or increasing fan speed"
                    } else {
                        summary += " - consider improving ventilation"
                    }
                } else if temperature < AppConstants.AI.coolTemperatureThreshold {
                    summary +=
                        ", running cool at \(temperature.rounded(.towardZero).formatted(.number.precision(.fractionLength(0))))°C with fan at \(fanSpeedPercent)%"
                } else {
                    summary +=
                        ", running at a stable \(temperature.rounded(.towardZero).formatted(.number.precision(.fractionLength(0))))°C with fan at \(fanSpeedPercent)%"
                }

            } else {
                summary += ", temperature unavailable"
            }
            if let power, power.isFinite {
                summary +=
                    " while consuming \(power.rounded(.towardZero).formatted(.number.precision(.fractionLength(0))))W of power."
            } else {
                summary += ", power unavailable."
            }
        }

        #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *), AIFeatureFlags.useFoundationModels,
                let session = languageSession as? LanguageModelSession
            {
                do {
                    let variation = try await generateDeviceSummaryVariation(
                        using: session,
                        hashRate: telemetry.hashrate,
                        temperature: temperature,
                        power: power,
                        fanSpeed: fanSpeedPercent
                    )
                    lastGenerationFailed = false
                    lastErrorMessage = nil
                    return AISummary(
                        content: appendingMiningLuckSentence(
                            miningLuckSentence,
                            to: variation
                        )
                    )
                } catch {
                    lastGenerationFailed = true
                    lastErrorMessage = "Generation failed"
                    // Fall back to basic summary
                }
            }
        #endif

        return AISummary(
            content: appendingMiningLuckSentence(
                miningLuckSentence,
                to: summary
            )
        )
    }

    private func appendingMiningLuckSentence(_ luckSentence: String?, to summary: String) -> String {
        guard let luckSentence else {
            return summary
        }

        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSummary.isEmpty else {
            return luckSentence
        }

        let separator: String
        if trimmedSummary.hasSuffix(".")
            || trimmedSummary.hasSuffix("!")
            || trimmedSummary.hasSuffix("?")
        {
            separator = " "
        } else {
            separator = ". "
        }

        return "\(trimmedSummary)\(separator)\(luckSentence)"
    }

    private func analyzeHistoricalTrend(
        historicalData: [HistoricalDataPoint]
    ) -> String {
        guard historicalData.count >= 2 else { return "" }

        let sorted = historicalData.sorted { $0.timestamp < $1.timestamp }
        guard let start = sorted.first?.timestamp, let end = sorted.last?.timestamp, end > start
        else { return "" }

        let duration = end.timeIntervalSince(start)
        if duration < 10 * 60 { return "" }

        let average = sorted.map { $0.hashrate }.reduce(0, +) / Double(sorted.count)
        let avgFormatted = average.formattedHashRateWithUnit()
        let windowText = formatDuration(seconds: duration)

        return
            "Averaged \(avgFormatted.value) \(avgFormatted.unit) across samples spanning \(windowText)."
    }

    private func formatDuration(seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let days = totalSeconds / 86_400
        if days >= 1 {
            return days == 1 ? "1 day" : "\(days) days"
        }
        let hours = totalSeconds / 3_600
        if hours >= 1 {
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        let minutes = totalSeconds / 60
        if minutes >= 1 {
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        return "less than a minute"
    }

    // MARK: - Foundation Models Integration

    #if canImport(FoundationModels)
        @available(iOS 26.0, macOS 26.0, *)
        private func generateDeviceSummaryVariation(
            using session: LanguageModelSession,
            hashRate: Double?,
            temperature: Double?,
            power: Double?,
            fanSpeed: Int
        ) async throws -> String {
            let hashRateText =
                hashRate.map {
                    let formatted = $0.formattedHashRateWithUnit()
                    return "\(formatted.value) \(formatted.unit)"
                } ?? "Unavailable"
            let temperatureText =
                temperature.flatMap { $0.isFinite ? $0 : nil }.map {
                    "\($0.rounded(.towardZero).formatted(.number.precision(.fractionLength(0))))°C"
                } ?? "Unavailable"
            let powerText =
                power.flatMap { $0.isFinite ? $0 : nil }.map {
                    "\($0.rounded(.towardZero).formatted(.number.precision(.fractionLength(0))))W"
                } ?? "Unavailable"
            let prompt = """
                Create a miner summary with these details:
                - Current hashrate: \(hashRateText)
                - Temperature: \(temperatureText)
                - Fan speed: \(fanSpeed)%
                - Power consumption: \(powerText)

                Requirements:
                - Include all technical numbers exactly
                - Keep it conversational and natural
                - Under 40 words
                - No introductory phrases
                """

            let response = try await session.respond(
                to: prompt,
                generating: MinerSummaryOutput.self
            )
            return response.content.summary
        }

        @available(iOS 26.0, macOS 26.0, *)
        private func generateFleetSummaryVariation(
            using session: LanguageModelSession,
            basicData: String
        ) async throws -> String {
            let prompt = basicData

            let response = try await session.respond(
                to: prompt,
                generating: MinerSummaryOutput.self
            )
            return response.content.summary
        }
    #endif

}
