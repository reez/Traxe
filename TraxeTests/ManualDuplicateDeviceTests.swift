import Foundation
import XCTest

@testable import Traxe

@MainActor
final class ManualDuplicateDeviceTests: XCTestCase {
    func testNewDeviceSaveRejectsSameAddressWithoutReplacingIdentity() throws {
        let suite = "ManualDuplicateDeviceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let previousShared = DeviceManagementService.sharedDefaultsOverride
        let previousOnboarding = DeviceManagementService.onboardingDefaultsOverride
        let previousReload = DeviceManagementService.reloadWidgetTimelines
        DeviceManagementService.sharedDefaultsOverride = defaults
        DeviceManagementService.onboardingDefaultsOverride = defaults
        DeviceManagementService.reloadWidgetTimelines = { _ in }
        defer {
            DeviceManagementService.sharedDefaultsOverride = previousShared
            DeviceManagementService.onboardingDefaultsOverride = previousOnboarding
            DeviceManagementService.reloadWidgetTimelines = previousReload
            defaults.removePersistentDomain(forName: suite)
        }
        let original = SavedDevice(
            name: "Original",
            ipAddress: "192.168.1.10",
            macAddress: "AA:BB:CC:DD:EE:01"
        )
        let data = try JSONEncoder().encode([original])
        defaults.set(data, forKey: "savedDevices")
        for mac in ["AA:BB:CC:DD:EE:01", "AA:BB:CC:DD:EE:02"] {
            XCTAssertThrowsError(
                try DeviceManagementService.saveNewDevice(
                    SavedDevice(name: "Candidate", ipAddress: original.ipAddress, macAddress: mac)
                )
            ) { error in
                guard case DeviceSaveError.addressAlreadySaved = error else {
                    return XCTFail("Expected duplicate address, received \(error)")
                }
            }
            XCTAssertEqual(defaults.data(forKey: "savedDevices"), data)
            XCTAssertFalse(defaults.bool(forKey: "hasCompletedOnboarding"))
        }
        // Selecting an existing miner during onboarding still completes that flow.
        try DeviceManagementService.saveDevice(original)
        XCTAssertTrue(defaults.bool(forKey: "hasCompletedOnboarding"))
    }

    func testManualAddPropagatesDuplicateDetectedAfterDeviceRequest() async throws {
        var dependencies = OnboardingViewModel.Dependencies.live
        dependencies.urlSession = .init(data: { _ in throw URLError(.notConnectedToInternet) })
        dependencies.notificationCenter = NotificationCenter()
        dependencies.deviceManagement = .init(
            checkDevice: { ip in
                DiscoveredDevice(
                    ip: ip,
                    name: "Miner",
                    hashrate: 700,
                    temperature: 50,
                    bestDiff: "2 M",
                    power: 15,
                    poolURL: nil,
                    blockHeight: nil,
                    networkDifficulty: nil
                )
            },
            saveDevice: { _ in XCTFail("Manual Add must require a new saved address") },
            saveDevices: { _ in },
            saveNewDevice: { _ in throw DeviceSaveError.addressAlreadySaved }
        )
        let model = OnboardingViewModel(dependencies: dependencies)
        do {
            _ = try await model.checkAndSaveDevice(ip: "192.168.1.10", requireNewDevice: true)
            XCTFail("The add sheet must receive the duplicate error instead of dismissing")
        } catch DeviceSaveError.addressAlreadySaved {
        }
    }
}
