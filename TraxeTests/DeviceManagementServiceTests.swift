import Foundation
import XCTest

@testable import Traxe

final class DeviceManagementServiceTests: XCTestCase {
    private var sharedDefaults: UserDefaults!
    private var onboardingDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        sharedDefaults = makeIsolatedDefaults(suiteName: "DeviceManagementServiceTests.shared")
        onboardingDefaults = makeIsolatedDefaults(
            suiteName: "DeviceManagementServiceTests.onboarding"
        )

        DeviceManagementService.sharedDefaultsOverride = sharedDefaults
        DeviceManagementService.onboardingDefaultsOverride = onboardingDefaults
        DeviceManagementService.reloadWidgetTimelines = { _ in }
    }

    override func tearDown() {
        DeviceManagementService.sharedDefaultsOverride = nil
        DeviceManagementService.onboardingDefaultsOverride = nil
        DeviceManagementService.reloadWidgetTimelines = { _ in }
        sharedDefaults = nil
        onboardingDefaults = nil
        super.tearDown()
    }

    func testSaveDeviceWritesSavedDevicesAndSavedDeviceIPsAndUpdatesSelectedIP() throws {
        let device = SavedDevice(name: "Miner A", ipAddress: "192.168.1.10")

        try DeviceManagementService.saveDevice(device)

        XCTAssertEqual(storedDevices(), [device])
        XCTAssertEqual(
            sharedDefaults.array(forKey: "savedDeviceIPs") as? [String],
            [device.ipAddress]
        )
        XCTAssertEqual(
            sharedDefaults.string(forKey: "bitaxeIPAddress"),
            device.ipAddress
        )
        XCTAssertTrue(onboardingDefaults.bool(forKey: "hasCompletedOnboarding"))
    }

    func testSaveDevicesWritesUniqueDevicesAndUpdatesSelectedIPToFirstNewDevice() throws {
        let existing = SavedDevice(name: "Miner A", ipAddress: "192.168.1.10")
        let second = SavedDevice(name: "Miner B", ipAddress: "192.168.1.11")
        let third = SavedDevice(name: "Miner C", ipAddress: "192.168.1.12")
        try seedSavedDevices([existing], selectedIP: existing.ipAddress)

        try DeviceManagementService.saveDevices([existing, second, third, second])

        XCTAssertEqual(storedDevices(), [existing, second, third])
        XCTAssertEqual(
            sharedDefaults.array(forKey: "savedDeviceIPs") as? [String],
            [existing.ipAddress, second.ipAddress, third.ipAddress]
        )
        XCTAssertEqual(sharedDefaults.string(forKey: "bitaxeIPAddress"), second.ipAddress)
        XCTAssertTrue(onboardingDefaults.bool(forKey: "hasCompletedOnboarding"))
    }

    func testSaveDevicesPreservesSelectionWhenAllDevicesAlreadyExist() throws {
        let first = SavedDevice(name: "Miner A", ipAddress: "192.168.1.10")
        let second = SavedDevice(name: "Miner B", ipAddress: "192.168.1.11")
        try seedSavedDevices([first, second], selectedIP: first.ipAddress)

        try DeviceManagementService.saveDevices([second, first])

        XCTAssertEqual(storedDevices(), [first, second])
        XCTAssertEqual(sharedDefaults.string(forKey: "bitaxeIPAddress"), first.ipAddress)
        XCTAssertFalse(onboardingDefaults.bool(forKey: "hasCompletedOnboarding"))
    }

    func testDeleteDevicePreservesSelectedIPWhenDeletingDifferentDevice() throws {
        let first = SavedDevice(name: "Miner A", ipAddress: "192.168.1.10")
        let second = SavedDevice(name: "Miner B", ipAddress: "192.168.1.11")

        try seedSavedDevices([first, second], selectedIP: first.ipAddress)

        try DeviceManagementService.deleteDevice(ipAddressToDelete: second.ipAddress)

        XCTAssertEqual(storedDevices(), [first])
        XCTAssertEqual(
            sharedDefaults.array(forKey: "savedDeviceIPs") as? [String],
            [first.ipAddress]
        )
        XCTAssertEqual(sharedDefaults.string(forKey: "bitaxeIPAddress"), first.ipAddress)
    }

    func testDeleteDeviceClearsSelectedIPWhenDeletingCurrentDevice() throws {
        let first = SavedDevice(name: "Miner A", ipAddress: "192.168.1.10")
        let second = SavedDevice(name: "Miner B", ipAddress: "192.168.1.11")

        try seedSavedDevices([first, second], selectedIP: second.ipAddress)

        try DeviceManagementService.deleteDevice(ipAddressToDelete: second.ipAddress)

        XCTAssertEqual(storedDevices(), [first])
        XCTAssertEqual(
            sharedDefaults.array(forKey: "savedDeviceIPs") as? [String],
            [first.ipAddress]
        )
        XCTAssertNil(sharedDefaults.string(forKey: "bitaxeIPAddress"))
    }

    func testDeleteDeviceRemovesOnlyThatMinersAlertPreference() throws {
        let first = SavedDevice(name: "Miner A", ipAddress: "192.168.1.10")
        let second = SavedDevice(name: "Miner B", ipAddress: "192.168.1.11")
        try seedSavedDevices([first, second], selectedIP: first.ipAddress)
        let preferences = MinerAlertPreferences(defaults: sharedDefaults)
        preferences.setEnabled(true, for: first.ipAddress)
        preferences.setEnabled(true, for: second.ipAddress)

        try DeviceManagementService.deleteDevice(ipAddressToDelete: second.ipAddress)

        XCTAssertEqual(preferences.enabledIPAddresses, [first.ipAddress])
    }

    private func seedSavedDevices(_ devices: [SavedDevice], selectedIP: String?) throws {
        let data = try JSONEncoder().encode(devices)
        sharedDefaults.set(data, forKey: "savedDevices")
        sharedDefaults.set(devices.map(\.ipAddress), forKey: "savedDeviceIPs")
        if let selectedIP {
            sharedDefaults.set(selectedIP, forKey: "bitaxeIPAddress")
        } else {
            sharedDefaults.removeObject(forKey: "bitaxeIPAddress")
        }
    }

    private func storedDevices() -> [SavedDevice] {
        guard let data = sharedDefaults.data(forKey: "savedDevices") else { return [] }
        return (try? JSONDecoder().decode([SavedDevice].self, from: data)) ?? []
    }

    private func makeIsolatedDefaults(suiteName: String) -> UserDefaults {
        let uniqueSuiteName = "\(suiteName).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: uniqueSuiteName) else {
            fatalError("Failed to create isolated defaults suite: \(uniqueSuiteName)")
        }
        defaults.removePersistentDomain(forName: uniqueSuiteName)
        return defaults
    }
}
