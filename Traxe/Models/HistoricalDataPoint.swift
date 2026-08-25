import Foundation
import SwiftData

@Model
final class HistoricalDataPoint {
    #Index<HistoricalDataPoint>([\.timestamp], [\.deviceId, \.timestamp])

    var timestamp: Date
    var hashrate: Double
    var temperature: Double
    var deviceId: String?
    /// Identifies the last address move that rewrote this point, so a batch of
    /// moves can be resumed without moving the same point twice.
    var relocationOperationID: String? = nil

    init(timestamp: Date = Date(), hashrate: Double, temperature: Double, deviceId: String? = nil) {
        self.timestamp = timestamp
        self.hashrate = hashrate
        self.temperature = temperature
        self.deviceId = deviceId
    }
}
