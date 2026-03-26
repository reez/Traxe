import Foundation

struct WeeklyRecapFleetRecap: Identifiable, Sendable {
    let id: String
    let name: String
    let poolName: String?
    let currentHashrate: Double
    let recap: WeeklyRecap?
}
