import Foundation

struct DeviceGridItem: Identifiable, Equatable {
    let id: String
    let device: SavedDevice
    let savedDeviceIndex: Int
    let bestDifficultyRank: Int?
}
