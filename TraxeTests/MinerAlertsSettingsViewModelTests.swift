import Foundation
import UserNotifications
import XCTest

@testable import Traxe

@MainActor
final class MinerAlertsSettingsViewModelTests: XCTestCase {
    func testEnablingAlertsRequestsAuthorizationWhenItIsUndetermined() async throws {
        let suiteName = "MinerAlertsSettingsViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = MinerAlertsSettingsViewModel(
            ipAddress: "192.168.1.10",
            preferences: MinerAlertPreferences(defaults: defaults),
            authorization: MinerAlertNotificationAuthorization(
                currentStatus: { .notDetermined },
                requestAuthorization: { .authorized }
            ),
            reloadWidgetTimelines: {}
        )

        await viewModel.setEnabled(true)

        XCTAssertTrue(viewModel.isEnabled)
        XCTAssertFalse(viewModel.showsNotificationAccessWarning)
        XCTAssertTrue(MinerAlertPreferences(defaults: defaults).isEnabled(for: "192.168.1.10"))
    }

    func testEnablingAlertsSkipsTheAuthorizationRequestOnceItIsDetermined() async throws {
        let suiteName = "MinerAlertsSettingsViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = MinerAlertsSettingsViewModel(
            ipAddress: "192.168.1.10",
            preferences: MinerAlertPreferences(defaults: defaults),
            authorization: MinerAlertNotificationAuthorization(
                currentStatus: { .authorized },
                // A second prompt is impossible on iOS, so requesting again would be a bug.
                requestAuthorization: { .denied }
            ),
            reloadWidgetTimelines: {}
        )

        await viewModel.setEnabled(true)

        XCTAssertTrue(viewModel.isEnabled)
        XCTAssertFalse(viewModel.showsNotificationAccessWarning)
    }

    func testDeniedAuthorizationLeavesAlertsOffAndWarnsTheUser() async throws {
        let suiteName = "MinerAlertsSettingsViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = MinerAlertsSettingsViewModel(
            ipAddress: "192.168.1.10",
            preferences: MinerAlertPreferences(defaults: defaults),
            authorization: MinerAlertNotificationAuthorization(
                currentStatus: { .notDetermined },
                requestAuthorization: { .denied }
            ),
            reloadWidgetTimelines: {}
        )

        await viewModel.setEnabled(true)

        XCTAssertFalse(viewModel.isEnabled)
        XCTAssertTrue(viewModel.showsNotificationAccessWarning)
        XCTAssertFalse(MinerAlertPreferences(defaults: defaults).isEnabled(for: "192.168.1.10"))
    }

    func testRevokedAuthorizationWarnsWithoutSilentlyChangingTheStoredPreference() async throws {
        let suiteName = "MinerAlertsSettingsViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        MinerAlertPreferences(defaults: defaults).setEnabled(true, for: "192.168.1.10")
        let viewModel = MinerAlertsSettingsViewModel(
            ipAddress: "192.168.1.10",
            preferences: MinerAlertPreferences(defaults: defaults),
            authorization: MinerAlertNotificationAuthorization(
                currentStatus: { .denied },
                requestAuthorization: { .denied }
            ),
            reloadWidgetTimelines: {}
        )

        await viewModel.refresh()

        XCTAssertTrue(viewModel.isEnabled)
        XCTAssertTrue(viewModel.showsNotificationAccessWarning)
        XCTAssertTrue(MinerAlertPreferences(defaults: defaults).isEnabled(for: "192.168.1.10"))
    }

    func testUntouchedToggleDoesNotWarnAboutNotificationPermission() async throws {
        let suiteName = "MinerAlertsSettingsViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = MinerAlertsSettingsViewModel(
            ipAddress: "192.168.1.10",
            preferences: MinerAlertPreferences(defaults: defaults),
            authorization: MinerAlertNotificationAuthorization(
                currentStatus: { .denied },
                requestAuthorization: { .denied }
            ),
            reloadWidgetTimelines: {}
        )

        await viewModel.refresh()

        XCTAssertFalse(viewModel.isEnabled)
        XCTAssertFalse(viewModel.showsNotificationAccessWarning)
    }

    func testEnablingOneMinerDoesNotChangeAnotherMinersPreference() async throws {
        let suiteName = "MinerAlertsSettingsViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = MinerAlertPreferences(defaults: defaults)
        preferences.setEnabled(true, for: "192.168.1.11")
        let viewModel = MinerAlertsSettingsViewModel(
            ipAddress: "192.168.1.10",
            preferences: preferences,
            authorization: MinerAlertNotificationAuthorization(
                currentStatus: { .authorized },
                requestAuthorization: { .authorized }
            ),
            reloadWidgetTimelines: {}
        )

        await viewModel.setEnabled(true)

        XCTAssertEqual(preferences.enabledIPAddresses, ["192.168.1.10", "192.168.1.11"])
    }

    func testDisableWhilePermissionIsPendingWinsOverTheOlderEnable() async throws {
        let suiteName = "MinerAlertsSettingsViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = MinerAlertPreferences(defaults: defaults)
        // The authorization lookup parks until the test releases it, so the disable
        // below is guaranteed to happen while the enable is still suspended.
        let (permissionReadStream, permissionReadContinuation) = AsyncStream<Void>.makeStream()
        let (permissionResultStream, permissionResultContinuation) = AsyncStream<
            UNAuthorizationStatus
        >.makeStream()
        var permissionReads = permissionReadStream.makeAsyncIterator()
        let viewModel = MinerAlertsSettingsViewModel(
            ipAddress: "192.168.1.10",
            preferences: preferences,
            authorization: MinerAlertNotificationAuthorization(
                currentStatus: {
                    permissionReadContinuation.yield(())
                    var results = permissionResultStream.makeAsyncIterator()
                    return await results.next() ?? .notDetermined
                },
                requestAuthorization: { .authorized }
            ),
            reloadWidgetTimelines: {}
        )

        let enableTask = Task { await viewModel.setEnabled(true) }
        await permissionReads.next()
        await viewModel.setEnabled(false)
        permissionResultContinuation.yield(.authorized)
        await enableTask.value

        XCTAssertFalse(viewModel.isEnabled)
        XCTAssertFalse(viewModel.toggleIsOn)
        XCTAssertFalse(viewModel.isRequestInFlight)
        XCTAssertFalse(preferences.isEnabled(for: "192.168.1.10"))
    }

    func testToggleShowsTheRequestedValueUntilThePermissionAnswerArrives() async throws {
        let suiteName = "MinerAlertsSettingsViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let (permissionReadStream, permissionReadContinuation) = AsyncStream<Void>.makeStream()
        let (permissionResultStream, permissionResultContinuation) = AsyncStream<
            UNAuthorizationStatus
        >.makeStream()
        var permissionReads = permissionReadStream.makeAsyncIterator()
        let viewModel = MinerAlertsSettingsViewModel(
            ipAddress: "192.168.1.10",
            preferences: MinerAlertPreferences(defaults: defaults),
            authorization: MinerAlertNotificationAuthorization(
                currentStatus: {
                    permissionReadContinuation.yield(())
                    var results = permissionResultStream.makeAsyncIterator()
                    return await results.next() ?? .notDetermined
                },
                requestAuthorization: { .denied }
            ),
            reloadWidgetTimelines: {}
        )

        let enableTask = Task { await viewModel.setEnabled(true) }
        await permissionReads.next()

        XCTAssertTrue(viewModel.toggleIsOn)
        XCTAssertTrue(viewModel.isRequestInFlight)

        permissionResultContinuation.yield(.denied)
        await enableTask.value

        XCTAssertFalse(viewModel.toggleIsOn)
        XCTAssertFalse(viewModel.isRequestInFlight)
        XCTAssertTrue(viewModel.showsNotificationAccessWarning)
    }
}
