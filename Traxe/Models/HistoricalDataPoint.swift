import Foundation
import SwiftData

@Model
final class HistoricalDataPoint {
    var timestamp: Date
    var hashrate: Double
    var temperature: Double

    init(timestamp: Date = Date(), hashrate: Double, temperature: Double) {
        self.timestamp = timestamp
        self.hashrate = hashrate
        self.temperature = temperature
    }
}
