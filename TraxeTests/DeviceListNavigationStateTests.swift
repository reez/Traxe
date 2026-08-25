import SwiftUI
import XCTest

@testable import Traxe

@MainActor
final class DeviceListNavigationStateTests: XCTestCase {
    func testInitialCompactColumnIsSidebarWithFleetRecapAsDefaultDetail() {
        let navigation = DeviceListNavigationState()

        XCTAssertEqual(navigation.preferredCompactColumn, .sidebar)
        XCTAssertNil(navigation.selectedFeature)
        XCTAssertEqual(navigation.detailFeature, .fleetRecap)
    }

    func testSelectingMinerChoosesDetailColumnAndKeepsSelectionWhenBackRevealsSidebar() {
        var navigation = DeviceListNavigationState()

        navigation.select(.miner(ipAddress: "192.168.1.10"))

        XCTAssertEqual(navigation.preferredCompactColumn, .detail)
        XCTAssertEqual(navigation.selectedFeature, .miner(ipAddress: "192.168.1.10"))
        XCTAssertEqual(navigation.detailFeature, .miner(ipAddress: "192.168.1.10"))

        // Back is a column change made by NavigationSplitView; the selection stays put.
        navigation.preferredCompactColumn = .sidebar

        XCTAssertEqual(navigation.selectedFeature, .miner(ipAddress: "192.168.1.10"))
        XCTAssertEqual(navigation.detailFeature, .miner(ipAddress: "192.168.1.10"))
    }

    func testWideningAfterCompactBackStillShowsRetainedMinerBesideDashboard() {
        var navigation = DeviceListNavigationState()
        navigation.select(.miner(ipAddress: "192.168.1.11"))
        navigation.preferredCompactColumn = .sidebar

        // Widening does not touch the state: the expanded layout renders the sidebar and
        // `detailFeature` at the same time, so the retained miner reappears beside it.
        XCTAssertEqual(navigation.detailFeature, .miner(ipAddress: "192.168.1.11"))

        // Collapsing again keeps the dashboard visible rather than jumping to the miner.
        XCTAssertEqual(navigation.preferredCompactColumn, .sidebar)
    }

    func testReselectingSameMinerAfterBackMovesBackToDetailColumn() {
        var navigation = DeviceListNavigationState()
        navigation.select(.miner(ipAddress: "192.168.1.12"))
        navigation.preferredCompactColumn = .sidebar

        navigation.select(.miner(ipAddress: "192.168.1.12"))

        XCTAssertEqual(navigation.preferredCompactColumn, .detail)
        XCTAssertEqual(navigation.detailFeature, .miner(ipAddress: "192.168.1.12"))
    }

    func testSelectingFleetRecapFollowsTheSameColumnBehaviorAsAMiner() {
        var navigation = DeviceListNavigationState()

        navigation.select(.fleetRecap)

        XCTAssertEqual(navigation.preferredCompactColumn, .detail)
        XCTAssertEqual(navigation.selectedFeature, .fleetRecap)

        navigation.preferredCompactColumn = .sidebar

        XCTAssertEqual(navigation.selectedFeature, .fleetRecap)
        XCTAssertEqual(navigation.detailFeature, .fleetRecap)
    }

    func testDeletingSelectedMinerFallsBackToFleetRecapOnTheDashboard() {
        var navigation = DeviceListNavigationState()
        navigation.select(.miner(ipAddress: "192.168.1.13"))

        navigation.reconcileSelection(withSavedMinerIPAddresses: ["192.168.1.14"])

        XCTAssertNil(navigation.selectedFeature)
        XCTAssertEqual(navigation.detailFeature, .fleetRecap)
        XCTAssertEqual(navigation.preferredCompactColumn, .sidebar)
    }

    func testDeletingAnUnselectedMinerLeavesTheSelectionUntouched() {
        var navigation = DeviceListNavigationState()
        navigation.select(.miner(ipAddress: "192.168.1.14"))

        navigation.reconcileSelection(withSavedMinerIPAddresses: ["192.168.1.14"])

        XCTAssertEqual(navigation.selectedFeature, .miner(ipAddress: "192.168.1.14"))
        XCTAssertEqual(navigation.preferredCompactColumn, .detail)
    }

    func testFleetRecapSelectionSurvivesMinerDeletion() {
        var navigation = DeviceListNavigationState()
        navigation.select(.fleetRecap)

        navigation.reconcileSelection(withSavedMinerIPAddresses: [])

        XCTAssertEqual(navigation.selectedFeature, .fleetRecap)
        XCTAssertEqual(navigation.preferredCompactColumn, .detail)
    }

    func testEditModeDeletingTheRetainedMinerFallsBackInsteadOfKeepingStaleDetail() {
        // Reproduces the dashboard flow: select a miner, tap Back so the selection is
        // retained, then delete that miner from the edit-mode list. The edit-mode list
        // calls `deleteDevices(withIPAddresses:)`, exactly as this test does.
        let uniqueSuiteName = "DeviceListNavigationStateTests.editModeDelete.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: uniqueSuiteName) else {
            return XCTFail("Failed to create isolated defaults suite: \(uniqueSuiteName)")
        }
        defaults.removePersistentDomain(forName: uniqueSuiteName)
        defer { defaults.removePersistentDomain(forName: uniqueSuiteName) }

        let viewModel = DeviceListViewModel(
            defaults: defaults,
            dependencies: DeviceListViewModel.Dependencies(
                deviceManagement: .init(
                    checkDevice: { _ in throw DeviceCheckError.requestFailed(.timedOut) },
                    deleteDevice: { _ in },
                    reorderDevices: { _ in }
                ),
                reloadWidget: {},
                autoRefreshOnLoad: false
            )
        )
        viewModel.savedDevices = [
            SavedDevice(name: "Miner A", ipAddress: "192.168.1.20"),
            SavedDevice(name: "Miner B", ipAddress: "192.168.1.21"),
        ]

        var navigation = DeviceListNavigationState()
        navigation.select(.miner(ipAddress: "192.168.1.20"))
        navigation.preferredCompactColumn = .sidebar

        viewModel.deleteDevices(withIPAddresses: ["192.168.1.20"])
        navigation.reconcileSelection(
            withSavedMinerIPAddresses: Set(viewModel.savedDevices.map(\.ipAddress))
        )

        XCTAssertEqual(viewModel.savedDevices.map(\.ipAddress), ["192.168.1.21"])
        XCTAssertNil(navigation.selectedFeature)
        XCTAssertEqual(navigation.detailFeature, .fleetRecap)
        XCTAssertEqual(navigation.preferredCompactColumn, .sidebar)
    }

    func testEditModeDeletingAnUnselectedMinerKeepsTheSelectedMinerVisible() {
        let uniqueSuiteName =
            "DeviceListNavigationStateTests.editModeDeleteOther.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: uniqueSuiteName) else {
            return XCTFail("Failed to create isolated defaults suite: \(uniqueSuiteName)")
        }
        defaults.removePersistentDomain(forName: uniqueSuiteName)
        defer { defaults.removePersistentDomain(forName: uniqueSuiteName) }

        let viewModel = DeviceListViewModel(
            defaults: defaults,
            dependencies: DeviceListViewModel.Dependencies(
                deviceManagement: .init(
                    checkDevice: { _ in throw DeviceCheckError.requestFailed(.timedOut) },
                    deleteDevice: { _ in },
                    reorderDevices: { _ in }
                ),
                reloadWidget: {},
                autoRefreshOnLoad: false
            )
        )
        viewModel.savedDevices = [
            SavedDevice(name: "Miner A", ipAddress: "192.168.1.30"),
            SavedDevice(name: "Miner B", ipAddress: "192.168.1.31"),
        ]

        var navigation = DeviceListNavigationState()
        navigation.select(.miner(ipAddress: "192.168.1.30"))

        viewModel.deleteDevices(withIPAddresses: ["192.168.1.31"])
        navigation.reconcileSelection(
            withSavedMinerIPAddresses: Set(viewModel.savedDevices.map(\.ipAddress))
        )

        XCTAssertEqual(navigation.selectedFeature, .miner(ipAddress: "192.168.1.30"))
        XCTAssertEqual(navigation.preferredCompactColumn, .detail)
    }

    func testDashboardRefreshIsRequestedWhenCompactBackRevealsTheDashboard() {
        var navigation = DeviceListNavigationState()
        navigation.select(.miner(ipAddress: "192.168.1.16"))

        let previousColumn = navigation.preferredCompactColumn
        navigation.preferredCompactColumn = .sidebar

        XCTAssertTrue(
            DeviceListNavigationState.revealsDashboard(
                from: previousColumn,
                to: navigation.preferredCompactColumn
            )
        )
        // The refresh trigger does not depend on the selection being cleared.
        XCTAssertEqual(navigation.selectedFeature, .miner(ipAddress: "192.168.1.16"))
    }

    func testDashboardRefreshIsNotRequestedWhenMovingToTheDetailColumn() {
        var navigation = DeviceListNavigationState()

        let previousColumn = navigation.preferredCompactColumn
        navigation.select(.fleetRecap)

        XCTAssertFalse(
            DeviceListNavigationState.revealsDashboard(
                from: previousColumn,
                to: navigation.preferredCompactColumn
            )
        )
    }

    func testFailedConnectionClearingSelectionReturnsToTheDashboard() {
        var navigation = DeviceListNavigationState()
        navigation.select(.miner(ipAddress: "192.168.1.17"))

        navigation.clearSelection()

        XCTAssertNil(navigation.selectedFeature)
        XCTAssertEqual(navigation.preferredCompactColumn, .sidebar)
        XCTAssertEqual(navigation.detailFeature, .fleetRecap)
    }
}
