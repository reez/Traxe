import Foundation
import SwiftUI

struct DeviceMetrics {
    var hashrate: Double = 0.0
    var expectedHashrate: Double = 0.0
    var temperature: Double = 0.0
    var power: Double = 0.0
    var uptime: TimeInterval = 0
    var fanSpeedPercent: Int = 0
    var timestamp: Date = Date()
    var bestDifficulty: Double = 0.0
    var inputVoltage: Double = 0.0
    var asicVoltage: Double = 0.0
    var measuredVoltage: Double = 0.0
    var frequency: Double = 0.0
    var sharesAccepted: Int = 0
    var sharesRejected: Int = 0
    var poolURL: String? = nil
    var hostname: String? = nil
    var blockHeight: Int? = nil
    var networkDifficulty: Double? = nil
    var blockFound: Int? = nil

    var efficiency: Double {
        guard hashrate > 0 else { return 0 }
        return power / (hashrate / 1000.0)
    }

    var temperatureColor: Color {
        switch temperature {
        case ..<70: return .green
        case 70..<85: return .yellow
        default: return .red
        }
    }

    var formattedUptime: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: uptime) ?? "N/A"
    }

    init(
        hashrate: Double = 0.0,
        expectedHashrate: Double = 0.0,
        temperature: Double = 0.0,
        power: Double = 0.0,
        uptime: TimeInterval = 0,
        fanSpeedPercent: Int = 0,
        timestamp: Date = Date(),
        bestDifficulty: Double = 0.0,
        inputVoltage: Double = 0.0,
        asicVoltage: Double = 0.0,
        measuredVoltage: Double = 0.0,
        frequency: Double = 0.0,
        sharesAccepted: Int = 0,
        sharesRejected: Int = 0,
        poolURL: String? = nil,
        hostname: String? = nil,
        blockHeight: Int? = nil,
        networkDifficulty: Double? = nil,
        blockFound: Int? = nil
    ) {
        self.hashrate = hashrate
        self.expectedHashrate = expectedHashrate
        self.temperature = temperature
        self.power = power
        self.uptime = uptime
        self.fanSpeedPercent = fanSpeedPercent
        self.timestamp = timestamp
        self.bestDifficulty = bestDifficulty
        self.inputVoltage = inputVoltage
        self.asicVoltage = asicVoltage
        self.measuredVoltage = measuredVoltage
        self.frequency = frequency
        self.sharesAccepted = sharesAccepted
        self.sharesRejected = sharesRejected
        self.poolURL = poolURL
        self.hostname = hostname
        self.blockHeight = blockHeight
        self.networkDifficulty = networkDifficulty
        self.blockFound = blockFound
    }

    init(from systemInfo: SystemInfoDTO) {
        let inputVoltage = Self.normalizeVoltage(
            systemInfo.voltage ?? 0.0,
            threshold: 1_000.0  // allow higher-voltage rigs to report in volts
        )
        let asicVoltage = Self.normalizeVoltage(
            Double(systemInfo.coreVoltage ?? systemInfo.coreVoltageActual ?? 0),
            threshold: 200.0  // core voltages are typically ~1,000 mV
        )
        let measuredVoltage = {
            let rawMeasured = Double(systemInfo.coreVoltageActual ?? 0)
            if rawMeasured > 0 {
                return Self.normalizeVoltage(rawMeasured, threshold: 200.0)
            }
            if asicVoltage > 0 {
                return asicVoltage
            }
            return inputVoltage
        }()

        self.init(
            hashrate: systemInfo.hashrate ?? 0.0,
            expectedHashrate: 0.0,
            temperature: systemInfo.temp ?? 0.0,
            power: systemInfo.power ?? 0.0,
            uptime: TimeInterval(systemInfo.uptimeSeconds ?? 0),
            fanSpeedPercent: systemInfo.fanspeed ?? 0,
            timestamp: Date(),
            bestDifficulty: DeviceMetrics.parseBestDifficultyInMillions(systemInfo.bestDiff),
            inputVoltage: inputVoltage,
            asicVoltage: asicVoltage,
            measuredVoltage: measuredVoltage,
            frequency: Double(systemInfo.frequency ?? 0),
            sharesAccepted: systemInfo.sharesAccepted ?? 0,
            sharesRejected: systemInfo.sharesRejected ?? 0,
            poolURL: systemInfo.poolURL,
            hostname: systemInfo.hostname,
            blockHeight: systemInfo.blockHeight,
            networkDifficulty: systemInfo.networkDifficulty,
            blockFound: systemInfo.blockFound
        )
    }

    static var placeholder: DeviceMetrics {
        DeviceMetrics(
            hashrate: 580.5,
            expectedHashrate: 600.0,
            temperature: 65.2,
            power: 155.8,
            uptime: 86400 * 3 + 3600 * 5,
            fanSpeedPercent: 85
        )
    }
}

// MARK: - Utilities
extension DeviceMetrics {
    private static func normalizeVoltage(
        _ rawValue: Double,
        threshold: Double = 250.0
    ) -> Double {
        guard rawValue != 0 else { return 0 }
        // Anything this high is assumed to still be in mV; tweak per data source if needed
        let divisor = rawValue >= threshold ? 1000.0 : 1.0
        return rawValue / divisor
    }

    // Converts strings like "598.7M", "2.3G", "4,070,000 T" to a Double representing millions (M)
    fileprivate static func parseBestDifficultyInMillions(_ diffString: String) -> Double {
        let trimmed = diffString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0.0 }

        // Map suffix to multiplier in terms of M (millions)
        let multipliersInM: [Character: Double] = [
            "K": 0.001,
            "M": 1.0,
            "G": 1_000.0,
            "T": 1_000_000.0,
            "P": 1_000_000_000.0,
        ]

        var numericPart = trimmed
        var multiplier: Double = 1.0

        if let last = trimmed.last, let mult = multipliersInM[last.uppercased().first ?? last] {
            multiplier = mult
            numericPart = String(trimmed.dropLast())
        }

        let cleaned = numericPart.replacingOccurrences(of: ",", with: "")
        guard let value = Double(cleaned) else { return 0.0 }
        if multiplier == 1.0, trimmed.last?.isNumber == true {
            // No suffix: treat as raw diff and normalize to millions.
            return value / 1_000_000.0
        }
        return value * multiplier
    }
}
