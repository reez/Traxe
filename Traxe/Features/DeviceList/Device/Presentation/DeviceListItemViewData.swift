import Foundation

struct DeviceListItemViewData: Identifiable, Equatable {
    let id: String
    let title: String
    let ipAddress: String
    let hashrateValue: Double
    let hashrateValueText: String
    let hashrateUnitText: String
    let summaryHashrateText: String?
    let bestDifficultyRankText: String?
    let bestDifficultyRankIsHighlighted: Bool
    let showsBestDifficultyMetric: Bool
    let bestDifficultyValueText: String?
    let bestDifficultyUnitText: String?
    let showsPlaceholderHashrate: Bool
    let isReachable: Bool
    let isAccessible: Bool
    let showsLock: Bool
}
