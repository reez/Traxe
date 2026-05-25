import Foundation

enum DeviceListItemPresenter {
    static func makeViewData(
        device: SavedDevice,
        metrics: DeviceMetrics?,
        index: Int,
        reachableIPs: Set<String>,
        isLoadingAggregatedStats: Bool,
        subscriptionAccessPolicy: SubscriptionAccessPolicy,
        bestDifficultyRank: Int? = nil,
        sortOption: DeviceGridSortOption = .savedOrder,
        isPreview: Bool = ProcessInfo.isPreview
    ) -> DeviceListItemViewData {
        let hashrate = metrics?.hashrate ?? 0
        let displayValue = hashrate >= 1000 ? hashrate / 1000 : hashrate
        let displayUnit = hashrate >= 1000 ? "TH/s" : "GH/s"
        let formattedValue = displayValue.formatted(.number.precision(.fractionLength(1)))
        let hasMetrics = metrics != nil
        let bestDifficulty = metrics?.bestDifficulty ?? 0
        let showsBestDifficultyMetric =
            sortOption == .scoreboard
            && hasMetrics
            && bestDifficulty.isFinite
            && bestDifficulty > 0
        let formattedBestDifficulty = bestDifficulty.formattedDifficulty()
        let isAccessible = subscriptionAccessPolicy.isDeviceAccessible(at: index)
        let isReachable =
            isLoadingAggregatedStats
            || reachableIPs.contains(device.ipAddress)
            || (isPreview && metrics != nil)

        return DeviceListItemViewData(
            id: device.ipAddress,
            title: metrics?.hostname ?? device.name,
            ipAddress: device.ipAddress,
            hashrateValue: displayValue,
            hashrateValueText: hasMetrics ? formattedValue : "---",
            hashrateUnitText: displayUnit,
            summaryHashrateText: hasMetrics ? "\(formattedValue) \(displayUnit)" : nil,
            bestDifficultyRankText: bestDifficultyRank.map { "#\($0)" },
            bestDifficultyRankIsHighlighted: bestDifficultyRank == 1,
            showsBestDifficultyMetric: showsBestDifficultyMetric,
            bestDifficultyValueText: showsBestDifficultyMetric ? formattedBestDifficulty.value : nil,
            bestDifficultyUnitText: showsBestDifficultyMetric ? formattedBestDifficulty.unit : nil,
            showsPlaceholderHashrate: !hasMetrics,
            isReachable: isReachable,
            isAccessible: isAccessible,
            showsLock: !isAccessible && hasMetrics && subscriptionAccessPolicy.shouldShowLocks
        )
    }
}
