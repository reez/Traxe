import Foundation

enum DeviceGridSortOption: String, CaseIterable, Hashable, Identifiable {
    case savedOrder
    case scoreboard
    case hashrate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .savedOrder:
            "Custom"
        case .scoreboard:
            "Scoreboard"
        case .hashrate:
            "Hashrate"
        }
    }
}
