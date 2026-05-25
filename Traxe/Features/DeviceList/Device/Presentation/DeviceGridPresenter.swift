import Foundation

enum DeviceGridPresenter {
    static func makeItems(
        devices: [SavedDevice],
        metricsByIP: [String: DeviceMetrics],
        sortOption: DeviceGridSortOption
    ) -> [DeviceGridItem] {
        let bestDifficultyRanks =
            sortOption == .scoreboard
            ? makeBestDifficultyRanks(
                devices: devices,
                metricsByIP: metricsByIP
            )
            : [:]
        let items = devices.enumerated().map { offset, device in
            DeviceGridItem(
                id: device.ipAddress,
                device: device,
                savedDeviceIndex: offset,
                bestDifficultyRank: bestDifficultyRanks[device.ipAddress]
            )
        }

        switch sortOption {
        case .savedOrder:
            return items
        case .scoreboard:
            return ordered(items) { item in
                guard let bestDifficulty = metricsByIP[item.device.ipAddress]?.bestDifficulty,
                    bestDifficulty.isFinite,
                    bestDifficulty > 0
                else {
                    return nil
                }
                return bestDifficulty
            }
        case .hashrate:
            return ordered(items) { item in
                guard let hashrate = metricsByIP[item.device.ipAddress]?.hashrate,
                    hashrate.isFinite
                else {
                    return nil
                }
                return hashrate
            }
        }
    }

    private static func makeBestDifficultyRanks(
        devices: [SavedDevice],
        metricsByIP: [String: DeviceMetrics]
    ) -> [String: Int] {
        let rankedDevices = devices.enumerated()
            .compactMap { offset, device -> (offset: Int, device: SavedDevice, bestDifficulty: Double)? in
                guard let bestDifficulty = metricsByIP[device.ipAddress]?.bestDifficulty,
                    bestDifficulty.isFinite,
                    bestDifficulty > 0
                else {
                    return nil
                }
                return (offset, device, bestDifficulty)
            }
            .sorted { lhs, rhs in
                if lhs.bestDifficulty == rhs.bestDifficulty {
                    return lhs.offset < rhs.offset
                }
                return lhs.bestDifficulty > rhs.bestDifficulty
            }

        return Dictionary(
            uniqueKeysWithValues: rankedDevices.enumerated().map { offset, item in
                (item.device.ipAddress, offset + 1)
            }
        )
    }

    private static func ordered(
        _ items: [DeviceGridItem],
        by value: (DeviceGridItem) -> Double?
    ) -> [DeviceGridItem] {
        items.sorted { lhs, rhs in
            let lhsValue = value(lhs)
            let rhsValue = value(rhs)

            switch (lhsValue, rhsValue) {
            case let (.some(lhsValue), .some(rhsValue)):
                if lhsValue == rhsValue {
                    return lhs.savedDeviceIndex < rhs.savedDeviceIndex
                }
                return lhsValue > rhsValue
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.savedDeviceIndex < rhs.savedDeviceIndex
            }
        }
    }
}
