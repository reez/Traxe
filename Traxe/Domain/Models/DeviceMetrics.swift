import Foundation
import SwiftUI

// Represents the core metrics displayed in the UI
struct DeviceMetrics {
    var hashrate: Double = 0.0  // GH/s
    var temperature: Double = 0.0  // Celsius
    var power: Double = 0.0  // Watts
    var uptime: TimeInterval = 0  // Seconds as TimeInterval for easy formatting
    var fanSpeedPercent: Int = 0
    var timestamp: Date = Date()  // When these metrics were last updated
    var bestDifficulty: Double = 0.0  // M (millions)
    var inputVoltage: Double = 0.0  // V
    var asicVoltage: Double = 0.0  // V
    var measuredVoltage: Double = 0.0  // V
    var frequency: Double = 0.0  // MHz
    var sharesAccepted: Int = 0
    var sharesRejected: Int = 0

    // Computed property for efficiency (W/Th)
    var efficiency: Double {
        guard hashrate > 0 else { return 0 }
        // Convert hashrate from GH/s to TH/s by dividing by 1000
        return power / (hashrate / 1000.0)
    }

    var temperatureColor: Color {
        switch temperature {
        case ..<70: return .green
        case 70..<85: return .yellow
        default: return .red
        }
    }

    // Formatted uptime string
    var formattedUptime: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: uptime) ?? "N/A"
    }

    static var placeholder: DeviceMetrics {
        DeviceMetrics(
            hashrate: 580.5,
            temperature: 65.2,
            power: 155.8,
            uptime: 86400 * 3 + 3600 * 5,  // 3 days and 5 hours
            fanSpeedPercent: 85
        )
    }
}
