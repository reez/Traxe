import Foundation

struct DeviceListItemViewData: Identifiable, Equatable {
    let id: String
    let title: String
    let ipAddress: String
    let hashrateValue: Double
    let hashrateValueText: String
    let hashrateUnitText: String
    let summaryHashrateText: String?
    let showsPlaceholderHashrate: Bool
    let isReachable: Bool
    let isAccessible: Bool
    let showsLock: Bool
}
