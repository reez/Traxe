import Foundation

struct DeviceTimeRange: Codable {
    let deviceId: String
    let startTime: Date
    let endTime: Date?

    func contains(_ date: Date) -> Bool {
        if let endTime = endTime {
            return date >= startTime && date <= endTime
        } else {
            return date >= startTime
        }
    }
}
