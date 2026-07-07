import SwiftUI

/// Navigation state for the device list's two-column `NavigationSplitView`.
///
/// `NavigationSplitView` decides on its own when to collapse; this type never
/// inspects size classes or widths. It only records which feature is selected and
/// which column a collapsed layout shows, so a single navigation tree serves every
/// width and the same state survives collapse and expansion in both directions.
struct DeviceListNavigationState: Equatable {
    /// The explicitly selected feature, or `nil` when the dashboard has no selection.
    private(set) var selectedFeature: DeviceListFeature?

    /// The column a collapsed layout shows. `NavigationSplitView` writes back to this
    /// when the user taps Back, which reveals the dashboard without discarding
    /// `selectedFeature`.
    var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    init(
        selectedFeature: DeviceListFeature? = nil,
        preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    ) {
        self.selectedFeature = selectedFeature
        self.preferredCompactColumn = preferredCompactColumn
    }

    /// The feature the detail column renders. Without an explicit selection the fleet
    /// recap is the default detail, which is what a wide layout shows at launch.
    var detailFeature: DeviceListFeature { selectedFeature ?? .fleetRecap }

    /// Shows `feature` in the detail column and moves a collapsed layout to it.
    ///
    /// Reselecting the feature already shown still moves the column, so tapping the
    /// same miner after Back navigates again.
    mutating func select(_ feature: DeviceListFeature) {
        selectedFeature = feature
        preferredCompactColumn = .detail
    }

    /// Drops the selection and returns a collapsed layout to the dashboard.
    mutating func clearSelection() {
        selectedFeature = nil
        preferredCompactColumn = .sidebar
    }

    /// Falls back to the fleet recap when the selected miner is no longer saved, so no
    /// column keeps rendering a miner that was deleted.
    ///
    /// Reconciling against the saved miners covers every deletion path, including the
    /// edit-mode list, rather than only the paths that remember to report a deletion.
    /// This matters because a selection is retained after Back, so a miner deleted from
    /// the dashboard could otherwise reappear when the scene widens.
    mutating func reconcileSelection(withSavedMinerIPAddresses ipAddresses: Set<String>) {
        guard case .miner(let ipAddress) = selectedFeature,
            !ipAddresses.contains(ipAddress)
        else { return }

        clearSelection()
    }

    /// Whether a collapsed layout just moved back to the dashboard, which is when the
    /// aggregated fleet statistics need refreshing.
    ///
    /// This is deliberately independent of the selection: Back keeps the selected
    /// feature so it reappears beside the dashboard if the scene later widens.
    static func revealsDashboard(
        from previous: NavigationSplitViewColumn,
        to current: NavigationSplitViewColumn
    ) -> Bool {
        previous != .sidebar && current == .sidebar
    }
}
