import Foundation
import SwiftData

@Model
final class HistoricalDataPoint {
    var timestamp: Date
    var hashrate: Double  // Store as Double for precision (GH/s)
    var temperature: Double  // Store as Double (Celsius)
    // Add other metrics if needed for historical tracking later

    init(timestamp: Date = Date(), hashrate: Double, temperature: Double) {
        self.timestamp = timestamp
        self.hashrate = hashrate
        self.temperature = temperature
    }
}
