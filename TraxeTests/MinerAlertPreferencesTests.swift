import Foundation
import XCTest

@testable import Traxe

final class MinerAlertPreferencesTests: XCTestCase {
    func testEachMinerOptsInIndependently() throws {
        let suiteName = "MinerAlertPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = MinerAlertPreferences(defaults: defaults)

        preferences.setEnabled(true, for: "192.168.1.10")
        preferences.setEnabled(true, for: "192.168.1.11")
        preferences.setEnabled(false, for: "192.168.1.11")

        XCTAssertTrue(preferences.isEnabled(for: "192.168.1.10"))
        XCTAssertFalse(preferences.isEnabled(for: "192.168.1.11"))
        XCTAssertEqual(preferences.enabledIPAddresses, ["192.168.1.10"])
    }

    func testPreferencesArePersistedForOtherProcessesInTheSameAppGroup() throws {
        let suiteName = "MinerAlertPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        MinerAlertPreferences(defaults: defaults).setEnabled(true, for: "192.168.1.10")

        let widgetSidePreferences = MinerAlertPreferences(defaults: defaults)

        XCTAssertEqual(widgetSidePreferences.enabledIPAddresses, ["192.168.1.10"])
    }

    func testMinerWithoutAPreferenceDefaultsToAlertsOff() throws {
        let suiteName = "MinerAlertPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = MinerAlertPreferences(defaults: defaults)

        XCTAssertFalse(preferences.isEnabled(for: "192.168.1.10"))
        XCTAssertTrue(preferences.enabledIPAddresses.isEmpty)
    }

    func testLegacyGlobalOnMigratesToEveryMinerSavedAtMigrationTime() throws {
        let suiteName = "MinerAlertPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "miner_alerts_enabled")
        defaults.set(["192.168.1.10", "192.168.1.11"], forKey: "savedDeviceIPs")
        let preferences = MinerAlertPreferences(defaults: defaults)

        preferences.migrateLegacyGlobalPreferenceIfNeeded()

        XCTAssertEqual(preferences.enabledIPAddresses, ["192.168.1.10", "192.168.1.11"])
    }

    func testLegacyGlobalOffMigratesToNoEnabledMiners() throws {
        let suiteName = "MinerAlertPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "miner_alerts_enabled")
        defaults.set(["192.168.1.10", "192.168.1.11"], forKey: "savedDeviceIPs")
        let preferences = MinerAlertPreferences(defaults: defaults)

        preferences.migrateLegacyGlobalPreferenceIfNeeded()

        XCTAssertTrue(preferences.enabledIPAddresses.isEmpty)
    }

    func testMigrationRunsOnceSoMinersAddedLaterDefaultToAlertsOff() throws {
        let suiteName = "MinerAlertPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "miner_alerts_enabled")
        defaults.set(["192.168.1.10"], forKey: "savedDeviceIPs")
        let preferences = MinerAlertPreferences(defaults: defaults)
        preferences.migrateLegacyGlobalPreferenceIfNeeded()

        defaults.set(["192.168.1.10", "192.168.1.12"], forKey: "savedDeviceIPs")
        preferences.migrateLegacyGlobalPreferenceIfNeeded()

        XCTAssertEqual(preferences.enabledIPAddresses, ["192.168.1.10"])
    }

    func testMigrationDoesNotReEnableAMinerTheUserTurnedOff() throws {
        let suiteName = "MinerAlertPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "miner_alerts_enabled")
        defaults.set(["192.168.1.10"], forKey: "savedDeviceIPs")
        let preferences = MinerAlertPreferences(defaults: defaults)
        preferences.migrateLegacyGlobalPreferenceIfNeeded()

        preferences.setEnabled(false, for: "192.168.1.10")
        preferences.migrateLegacyGlobalPreferenceIfNeeded()

        XCTAssertTrue(preferences.enabledIPAddresses.isEmpty)
    }

    func testRemovingAPreferenceLeavesOtherMinersEnabled() throws {
        let suiteName = "MinerAlertPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = MinerAlertPreferences(defaults: defaults)
        preferences.setEnabled(true, for: "192.168.1.10")
        preferences.setEnabled(true, for: "192.168.1.11")

        preferences.removePreference(for: "192.168.1.10")

        XCTAssertEqual(preferences.enabledIPAddresses, ["192.168.1.11"])
    }
}
