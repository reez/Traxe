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

    func testRecordMACAddressStoresNormalizedIdentityAndPublishesItForTheWidget() throws {
        let device = SavedDevice(name: "Miner A", ipAddress: "192.168.1.10")
        try seedSavedDevices([device], selectedIP: device.ipAddress)

        try DeviceManagementService.recordMACAddress(
            "aa:bb:cc:dd:ee:ff",
            forDeviceAt: "192.168.1.10"
        )

        XCTAssertEqual(storedDevices().first?.macAddress, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(
            sharedDefaults.dictionary(forKey: "savedDeviceMACAddresses") as? [String: String],
            ["192.168.1.10": "AA:BB:CC:DD:EE:FF"]
        )
    }

    func testPersistentDeviceIDSurvivesMACDiscoveryAndRelocation() throws {
        let device = SavedDevice(name: "Miner B", ipAddress: "192.168.1.10")
        try DeviceManagementService.saveDevice(device)
        XCTAssertEqual(try XCTUnwrap(storedDevices().first).id, device.id)

        try DeviceManagementService.recordMACAddress(
            "aa:bb:cc:dd:ee:02",
            forDeviceAt: "192.168.1.10"
        )
        let identified = try XCTUnwrap(storedDevices().first)
        XCTAssertEqual(identified.id, device.id)
        XCTAssertEqual(identified.macAddress, "AA:BB:CC:DD:EE:02")

        let relocations = try DeviceManagementService.relocateDevices(matching: [
            DiscoveredDevice(
                ip: "192.168.1.50",
                name: "Miner B",
                hashrate: 1,
                temperature: 1,
                bestDiff: "0",
                power: 1,
                poolURL: nil,
                blockHeight: nil,
                networkDifficulty: nil,
                macAddress: "AA:BB:CC:DD:EE:02"
            )
        ])

        XCTAssertEqual(relocations.count, 1)
        let relocated = try XCTUnwrap(storedDevices().first)
        XCTAssertEqual(relocated.id, device.id)
        XCTAssertEqual(relocated.ipAddress, "192.168.1.50")
        XCTAssertEqual(relocated.macAddress, "AA:BB:CC:DD:EE:02")
    }

    func testAddressSwapPersistsOneRecoveryOperationWithBothNewAddresses() throws {
        let first = SavedDevice(
            name: "Miner A",
            ipAddress: "192.168.1.10",
            macAddress: "AA:BB:CC:DD:EE:01"
        )
        let second = SavedDevice(
            name: "Miner B",
            ipAddress: "192.168.1.11",
            macAddress: "AA:BB:CC:DD:EE:02"
        )
        try seedSavedDevices([first, second], selectedIP: first.ipAddress)

        _ = try DeviceManagementService.relocateDevices(matching: [
            DiscoveredDevice(
                ip: "192.168.1.11", name: "Miner A", hashrate: 1,
                temperature: 1, bestDiff: "0", power: 1, poolURL: nil,
                blockHeight: nil, networkDifficulty: nil,
                macAddress: "AA:BB:CC:DD:EE:01"
            ),
            DiscoveredDevice(
                ip: "192.168.1.10", name: "Miner B", hashrate: 1,
                temperature: 1, bestDiff: "0", power: 1, poolURL: nil,
                blockHeight: nil, networkDifficulty: nil,
                macAddress: "AA:BB:CC:DD:EE:02"
            ),
        ])

        let persisted = storedDevices()
        XCTAssertEqual(persisted.map(\.ipAddress), ["192.168.1.11", "192.168.1.10"])
        XCTAssertEqual(persisted.map { $0.relocationRecords.count }, [1, 1])
        XCTAssertEqual(
            persisted[0].relocationRecords[0].operationID,
            persisted[1].relocationRecords[0].operationID
        )
        XCTAssertEqual(persisted[0].relocationRecords[0].previousIPAddress, "192.168.1.10")
        XCTAssertEqual(persisted[1].relocationRecords[0].previousIPAddress, "192.168.1.11")
    }

    func testRelocateDevicesMovesMinerFoundAtNewAddressAndCarriesKeyedStateAlong() throws {
        let moved = SavedDevice(
            name: "Miner A",
            ipAddress: "192.168.1.10",
            macAddress: "AA:BB:CC:DD:EE:01"
        )
        let stayed = SavedDevice(
            name: "Miner B",
            ipAddress: "192.168.1.11",
            macAddress: "AA:BB:CC:DD:EE:02"
        )
        try seedSavedDevices([moved, stayed], selectedIP: moved.ipAddress)
        sharedDefaults.set(["192.168.1.10"], forKey: "minerAlertEnabledIPAddressesV1")
        var reloadedKinds: [String] = []
        DeviceManagementService.reloadWidgetTimelines = { reloadedKinds.append($0) }

        let relocations = try DeviceManagementService.relocateDevices(matching: [
            DiscoveredDevice(
                ip: "192.168.1.42",
                name: "Miner A",
                hashrate: 1,
                temperature: 1,
                bestDiff: "0",
                power: 1,
                poolURL: nil,
                blockHeight: nil,
                networkDifficulty: nil,
                macAddress: "aa:bb:cc:dd:ee:01"
            ),
            DiscoveredDevice(
                ip: "192.168.1.11",
                name: "Miner B",
                hashrate: 1,
                temperature: 1,
                bestDiff: "0",
                power: 1,
                poolURL: nil,
                blockHeight: nil,
                networkDifficulty: nil,
                macAddress: "AA:BB:CC:DD:EE:02"
            ),
        ])

        XCTAssertEqual(
            relocations,
            [
                DeviceRelocation(
                    macAddress: "AA:BB:CC:DD:EE:01",
                    previousIPAddress: "192.168.1.10",
                    currentIPAddress: "192.168.1.42"
                )
            ]
        )
        XCTAssertEqual(storedDevices().map(\.ipAddress), ["192.168.1.42", "192.168.1.11"])
        XCTAssertEqual(storedDevices().map(\.name), ["Miner A", "Miner B"])
        XCTAssertEqual(
            sharedDefaults.array(forKey: "savedDeviceIPs") as? [String],
            ["192.168.1.42", "192.168.1.11"]
        )
        XCTAssertEqual(sharedDefaults.string(forKey: "bitaxeIPAddress"), "192.168.1.42")
        XCTAssertEqual(
            sharedDefaults.stringArray(forKey: "minerAlertEnabledIPAddressesV1"),
            ["192.168.1.42"]
        )
        XCTAssertEqual(
            SavedDeviceAddressAliases(defaults: sharedDefaults).currentAddress(for: "192.168.1.10"),
            "192.168.1.42"
        )
        XCTAssertEqual(reloadedKinds, ["TraxeWidget"])
    }

    func testRelocateDevicesAppliesSwappedAddressesTogether() throws {
        let first = SavedDevice(
            name: "Miner A",
            ipAddress: "192.168.1.10",
            macAddress: "AA:BB:CC:DD:EE:01"
        )
        let second = SavedDevice(
            name: "Miner B",
            ipAddress: "192.168.1.11",
            macAddress: "AA:BB:CC:DD:EE:02"
        )
        try seedSavedDevices([first, second], selectedIP: second.ipAddress)
        sharedDefaults.set(["192.168.1.11"], forKey: "minerAlertEnabledIPAddressesV1")

        let relocations = try DeviceManagementService.relocateDevices(matching: [
            DiscoveredDevice(
                ip: "192.168.1.11",
                name: "Miner A",
                hashrate: 1,
                temperature: 1,
                bestDiff: "0",
                power: 1,
                poolURL: nil,
                blockHeight: nil,
                networkDifficulty: nil,
                macAddress: "AA:BB:CC:DD:EE:01"
            ),
            DiscoveredDevice(
                ip: "192.168.1.10",
                name: "Miner B",
                hashrate: 1,
                temperature: 1,
                bestDiff: "0",
                power: 1,
                poolURL: nil,
                blockHeight: nil,
                networkDifficulty: nil,
                macAddress: "AA:BB:CC:DD:EE:02"
            ),
        ])

        XCTAssertEqual(relocations.count, 2)
        XCTAssertEqual(storedDevices().map(\.ipAddress), ["192.168.1.11", "192.168.1.10"])
        XCTAssertEqual(storedDevices().map(\.name), ["Miner A", "Miner B"])
        XCTAssertEqual(sharedDefaults.string(forKey: "bitaxeIPAddress"), "192.168.1.10")
        XCTAssertEqual(
            sharedDefaults.stringArray(forKey: "minerAlertEnabledIPAddressesV1"),
            ["192.168.1.10"]
        )
    }

    func testRelocateDevicesSkipsAmbiguousMACAndAddressStillHeldByAnotherMiner() throws {
        let duplicateA = SavedDevice(
            name: "Miner A",
            ipAddress: "192.168.1.10",
            macAddress: "AA:BB:CC:DD:EE:01"
        )
        let duplicateB = SavedDevice(
            name: "Miner A again",
            ipAddress: "192.168.1.12",
            macAddress: "AA:BB:CC:DD:EE:01"
        )
        let holder = SavedDevice(name: "Miner C", ipAddress: "192.168.1.30")
        let mover = SavedDevice(
            name: "Miner D",
            ipAddress: "192.168.1.40",
            macAddress: "AA:BB:CC:DD:EE:04"
        )
        try seedSavedDevices([duplicateA, duplicateB, holder, mover], selectedIP: nil)

        let relocations = try DeviceManagementService.relocateDevices(matching: [
            DiscoveredDevice(
                ip: "192.168.1.50",
                name: "Miner A",
                hashrate: 1,
                temperature: 1,
                bestDiff: "0",
                power: 1,
                poolURL: nil,
                blockHeight: nil,
                networkDifficulty: nil,
                macAddress: "AA:BB:CC:DD:EE:01"
            ),
            DiscoveredDevice(
                ip: "192.168.1.30",
                name: "Miner D",
                hashrate: 1,
                temperature: 1,
                bestDiff: "0",
                power: 1,
                poolURL: nil,
                blockHeight: nil,
                networkDifficulty: nil,
                macAddress: "AA:BB:CC:DD:EE:04"
            ),
        ])

        XCTAssertEqual(relocations, [])
        XCTAssertEqual(
            storedDevices().map(\.ipAddress),
            ["192.168.1.10", "192.168.1.12", "192.168.1.30", "192.168.1.40"]
        )
    }

    func testSaveDevicesTreatsKnownMACAtNewAddressAsMoveNotDuplicate() throws {
        let existing = SavedDevice(
            name: "Miner A",
            ipAddress: "192.168.1.10",
            macAddress: "AA:BB:CC:DD:EE:01"
        )
        try seedSavedDevices([existing], selectedIP: existing.ipAddress)

        try DeviceManagementService.saveDevices([
            SavedDevice(name: "Miner A", ipAddress: "192.168.1.77", macAddress: "aa:bb:cc:dd:ee:01")
        ])

        XCTAssertEqual(storedDevices().map(\.ipAddress), ["192.168.1.77"])
        XCTAssertEqual(
            sharedDefaults.array(forKey: "savedDeviceIPs") as? [String],
            ["192.168.1.77"]
        )
        XCTAssertEqual(sharedDefaults.string(forKey: "bitaxeIPAddress"), "192.168.1.77")
        XCTAssertFalse(onboardingDefaults.bool(forKey: "hasCompletedOnboarding"))
        XCTAssertEqual(
            SavedDeviceAddressAliases(defaults: sharedDefaults).currentAddress(for: "192.168.1.10"),
            "192.168.1.77"
        )
    }

    func testDeleteDeviceForgetsAliasesPointingAtDeletedAddress() throws {
        let device = SavedDevice(
            name: "Miner A",
            ipAddress: "192.168.1.20",
            macAddress: "AA:BB:CC:DD:EE:01"
        )
        try seedSavedDevices([device], selectedIP: nil)
        SavedDeviceAddressAliases(defaults: sharedDefaults).recordMoves([
            "192.168.1.10": "192.168.1.20"
        ])

        try DeviceManagementService.deleteDevice(ipAddressToDelete: "192.168.1.20")

        XCTAssertEqual(
            SavedDeviceAddressAliases(defaults: sharedDefaults).currentAddress(for: "192.168.1.10"),
            "192.168.1.10"
        )
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
