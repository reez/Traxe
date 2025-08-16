import Foundation
import SwiftUI

#if canImport(FoundationModels)
    import FoundationModels
#endif

@available(iOS 18.0, macOS 15.0, *)
actor AIAnalysisService {
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
                    do {
                        languageSession = LanguageModelSession(
                            instructions: """
                                You are a technical analyst. Write concise mining device summaries.

                                CRITICAL: Only output the summary text. NO introductory phrases.

                                Be natural and conversational while including all technical details.
                                """
                        )
                        lastGenerationFailed = false
                        lastErrorMessage = nil
                    } catch {
                        lastGenerationFailed = true
                        lastErrorMessage = "Failed to create session"
                    }
                case .unavailable(let reason):
                    languageSession = nil
                    lastGenerationFailed = true
                    lastErrorMessage =
                        switch reason {
                        case .deviceNotEligible:
                            "Device not compatible"
                        case .appleIntelligenceNotEnabled:
                            "Apple Intelligence not enabled"
                        case .modelNotReady:
                            "Model is downloading"
                        @unknown default:
                            "Model unavailable"
                        }
                @unknown default:
                    languageSession = nil
                    lastGenerationFailed = true
                    lastErrorMessage = "Unknown availability status"
                }
            }
        #endif
    }

    func refreshFoundationModelsSetup() async {
        await setupFoundationModels()
    }

    // MARK: - AI Summary Generation

    func generateFleetSummary(forDevices deviceIPs: [String]) async throws -> AISummary {

        var allDevices: [SystemInfoDTO] = []
        var totalHashRate: Double = 0
        var totalPower: Double = 0
        var avgTemperature: Double = 0
        var deviceCount = 0

        try await withThrowingTaskGroup(of: SystemInfoDTO?.self) { group in
            for ipAddress in deviceIPs {
                group.addTask { [self] in
                    do {
                        let systemInfo = try await networkService.fetchSystemInfo(
                            ipAddressOverride: ipAddress
                        )
                        return systemInfo
                    } catch {
                        return nil
                    }
                }
            }

            for try await systemInfo in group {
                if let systemInfo = systemInfo {
                    allDevices.append(systemInfo)
                    totalHashRate += systemInfo.hashRate ?? 0
                    totalPower += systemInfo.power ?? 0
                    avgTemperature += systemInfo.temp ?? 0
                    deviceCount += 1
                }
            }
        }

        guard deviceCount > 0 else {
            throw NSError(
                domain: "AIAnalysisService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No devices available for fleet analysis"]
            )
        }

        avgTemperature /= Double(deviceCount)

        // Try Foundation Models first if available

        #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *), AIFeatureFlags.useFoundationModels,
                let session = languageSession as? LanguageModelSession
            {
                do {
                    let basicSummary = AISummaryFormatter.fleetSummary(fromSystemInfos: allDevices)
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
        if let formatted = AISummaryFormatter.fleetSummary(fromSystemInfos: allDevices) {
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

        let systemInfo = try await networkService.fetchSystemInfo(ipAddressOverride: deviceIP)

        let hashRate = systemInfo.hashRate ?? 0
        let temperature = systemInfo.temp ?? 0
        let power = systemInfo.power ?? 0
        let fanSpeedPercent = systemInfo.fanspeed ?? 0

        let hashRateFormatted = hashRate.formattedHashRateWithUnit()
        var summary: String

        if !historicalData.isEmpty {
            let historicalTrend = analyzeHistoricalTrend(
                currentHashRate: hashRate,
                historicalData: historicalData
            )
            if !historicalTrend.isEmpty {
                summary = "Your device \(historicalTrend)."
            } else {
                // Fall back to current stats if trend is empty
                summary =
                    "Your device is producing \(hashRateFormatted.value) \(hashRateFormatted.unit)."
            }
        } else {
            // No historical data; show current stats
            summary =
                "Your device is producing \(hashRateFormatted.value) \(hashRateFormatted.unit)"

            if temperature > AppConstants.AI.hotTemperatureThreshold {
                summary += ", running warm at \(Int(temperature))°C with fan at \(fanSpeedPercent)%"
                if fanSpeedPercent < AppConstants.AI.lowFanSpeedThreshold {
                    summary += " - consider improving ventilation or increasing fan speed"
                } else {
                    summary += " - consider improving ventilation"
                }
            } else if temperature < AppConstants.AI.coolTemperatureThreshold {
                summary += ", running cool at \(Int(temperature))°C with fan at \(fanSpeedPercent)%"
            } else {
                summary +=
                    ", running at a stable \(Int(temperature))°C with fan at \(fanSpeedPercent)%"
            }

            summary += " while consuming \(Int(power))W of power."
        }

        #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *), AIFeatureFlags.useFoundationModels,
                let session = languageSession as? LanguageModelSession
            {
                do {
                    let variation = try await generateDeviceSummaryVariation(
                        using: session,
                        hashRate: hashRate,
                        temperature: temperature,
                        power: power,
                        fanSpeed: fanSpeedPercent,
                        historicalData: historicalData
                    )
                    lastGenerationFailed = false
                    lastErrorMessage = nil
                    return AISummary(content: variation)
                } catch {
                    lastGenerationFailed = true
                    lastErrorMessage = "Generation failed"
                    // Fall back to basic summary
                }
            }
        #endif

        return AISummary(content: summary)
    }

    private func analyzeHistoricalTrend(
        currentHashRate: Double,
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
            "has been averaging \(avgFormatted.value) \(avgFormatted.unit) over the last \(windowText)"
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
            hashRate: Double,
            temperature: Double,
            power: Double,
            fanSpeed: Int,
            historicalData: [HistoricalDataPoint]
        ) async throws -> String {
            let hashRateFormatted = hashRate.formattedHashRateWithUnit()
            let historicalTrend =
                !historicalData.isEmpty
                ? analyzeHistoricalTrend(currentHashRate: hashRate, historicalData: historicalData)
                : ""

            // Log actual historical data for verification
            if !historicalData.isEmpty {
                let sorted = historicalData.sorted { $0.timestamp < $1.timestamp }
                let actualAverage = sorted.map { $0.hashrate }.reduce(0, +) / Double(sorted.count)
                let actualRange = sorted.last!.timestamp.timeIntervalSince(sorted.first!.timestamp)
                let actualRangeFormatted = formatDuration(seconds: actualRange)
                let actualAverageFormatted = actualAverage.formattedHashRateWithUnit()

            }

            let prompt: String
            if !historicalData.isEmpty && !historicalTrend.isEmpty {
                // Only historical data
                prompt = """
                    Rewrite this historical mining performance summary to be more specific:
                    \(historicalTrend)

                    Requirements:
                    - Focus ONLY on historical averages and time periods
                    - Do NOT mention current hashrate
                    - Be very specific about the historical numbers and timeframe
                    - Keep it conversational and natural
                    - Under 20 words
                    - No introductory phrases
                    """
            } else {
                // Current stats (when no history)
                prompt = """
                    Create a mining device summary with these details:
                    - Current hashrate: \(hashRateFormatted.value) \(hashRateFormatted.unit)
                    - Temperature: \(Int(temperature))°C
                    - Fan speed: \(fanSpeed)%
                    - Power consumption: \(Int(power))W

                    Requirements:
                    - Include all technical numbers exactly
                    - Keep it conversational and natural
                    - Under 40 words
                    - No introductory phrases
                    """
            }

            let response = try await session.respond(to: prompt)
            return response.content
        }

        @available(iOS 26.0, macOS 26.0, *)
        private func generateFleetSummaryVariation(
            using session: LanguageModelSession,
            basicData: String
        ) async throws -> String {
            let prompt = basicData

            let response = try await session.respond(to: prompt)
            return response.content
        }
    #endif

}
