import Foundation
import SwiftData

@Model
final class HistoricalDataPoint {
    var timestamp: Date
    var hashrate: Double
    var temperature: Double
    var deviceId: String?

    init(timestamp: Date = Date(), hashrate: Double, temperature: Double, deviceId: String? = nil) {
        self.timestamp = timestamp
        self.hashrate = hashrate
        self.temperature = temperature
        self.deviceId = deviceId
    }
}
