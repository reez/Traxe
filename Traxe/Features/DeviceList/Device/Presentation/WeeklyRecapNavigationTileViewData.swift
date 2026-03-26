import Foundation

struct WeeklyRecapNavigationTileViewData: Equatable, Sendable {
    let title: String
    let subtitle: String
    let showsChevron: Bool

    static let fleet = WeeklyRecapNavigationTileViewData(
        title: "Weekly Recap",
        subtitle: "View all miners from the last 7 days",
        showsChevron: false
    )

    static let device = WeeklyRecapNavigationTileViewData(
        title: "Weekly Recap",
        subtitle: "View last 7 days with full charts",
        showsChevron: true
    )
}
