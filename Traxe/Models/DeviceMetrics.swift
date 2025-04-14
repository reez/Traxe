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
