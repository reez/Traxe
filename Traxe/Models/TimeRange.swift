import Foundation

enum TimeRange: String, CaseIterable, Identifiable {
    case lastHour = "1H"
    case lastDay = "24H"
    case lastWeek = "7D"

    var id: String { rawValue }

    var dateRange: Date {
        let now = Date()
        switch self {
        case .lastHour:
            return now.addingTimeInterval(-3600)
        case .lastDay:
            return now.addingTimeInterval(-86400)
        case .lastWeek:
            return now.addingTimeInterval(-604800)
        }
    }
}
