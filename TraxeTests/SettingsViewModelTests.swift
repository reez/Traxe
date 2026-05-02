import SwiftData
import XCTest

@testable import Traxe

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testDeleteCurrentMinerDeletesTrimmedSelectedIPAddressAndClearsSettingsState() throws {
        let sharedDefaults = makeIsolatedDefaults(suiteName: "SettingsViewModelTests.delete")
        sharedDefaults.set("192.168.1.10", forKey: "bitaxeIPAddress")
        let container = try makeInMemoryModelContainer()
        var deletedIPAddresses: [String] = []
        let viewModel = SettingsViewModel(
            sharedUserDefaults: sharedDefaults,
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false,
            deleteDevice: { ipAddressToDelete in
                deletedIPAddresses.append(ipAddressToDelete)
            }
        )
        viewModel.bitaxeIPAddress = " 192.168.1.10 "
        viewModel.currentVersion = "v2.6.0"
        viewModel.isConnected = true

        let deletedIPAddress = viewModel.deleteCurrentMiner()

        XCTAssertEqual(deletedIPAddress, "192.168.1.10")
        XCTAssertEqual(deletedIPAddresses, ["192.168.1.10"])
        XCTAssertEqual(viewModel.bitaxeIPAddress, "")
        XCTAssertEqual(viewModel.currentVersion, "Unknown")
        XCTAssertFalse(viewModel.isConnected)
        XCTAssertNil(sharedDefaults.string(forKey: "bitaxeIPAddress"))
        XCTAssertNil(viewModel.deleteMinerErrorMessage)
    }

    func testDeleteCurrentMinerUsesLoadedSelectionWhenConnectionFieldWasEdited() throws {
        let sharedDefaults = makeIsolatedDefaults(suiteName: "SettingsViewModelTests.edited")
        sharedDefaults.set("192.168.1.10", forKey: "bitaxeIPAddress")
        let container = try makeInMemoryModelContainer()
        var deletedIPAddresses: [String] = []
        let viewModel = SettingsViewModel(
            sharedUserDefaults: sharedDefaults,
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false,
            deleteDevice: { ipAddressToDelete in
                deletedIPAddresses.append(ipAddressToDelete)
            }
        )
        viewModel.bitaxeIPAddress = "192.168.1.99"

        let deletedIPAddress = viewModel.deleteCurrentMiner()

        XCTAssertEqual(deletedIPAddress, "192.168.1.10")
        XCTAssertEqual(deletedIPAddresses, ["192.168.1.10"])
    }

    func testDeleteCurrentMinerReturnsNilWhenNoMinerIsSelected() throws {
        let sharedDefaults = makeIsolatedDefaults(suiteName: "SettingsViewModelTests.noSelection")
        let container = try makeInMemoryModelContainer()
        let viewModel = SettingsViewModel(
            sharedUserDefaults: sharedDefaults,
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false,
            deleteDevice: { _ in
                XCTFail("Delete should not run without a selected miner.")
            }
        )

        let deletedIPAddress = viewModel.deleteCurrentMiner()

        XCTAssertNil(deletedIPAddress)
        XCTAssertEqual(viewModel.deleteMinerErrorMessage, "No miner is selected.")
    }

    func testDeleteCurrentMinerKeepsSelectionWhenDeleteFails() throws {
        let sharedDefaults = makeIsolatedDefaults(suiteName: "SettingsViewModelTests.failure")
        sharedDefaults.set("192.168.1.20", forKey: "bitaxeIPAddress")
        let container = try makeInMemoryModelContainer()
        let viewModel = SettingsViewModel(
            sharedUserDefaults: sharedDefaults,
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false,
            deleteDevice: { _ in
                throw TestDeleteError.failed
            }
        )

        let deletedIPAddress = viewModel.deleteCurrentMiner()

        XCTAssertNil(deletedIPAddress)
        XCTAssertEqual(viewModel.bitaxeIPAddress, "192.168.1.20")
        XCTAssertEqual(sharedDefaults.string(forKey: "bitaxeIPAddress"), "192.168.1.20")
        XCTAssertEqual(
            viewModel.deleteMinerErrorMessage,
            "Failed to delete miner: Delete failed."
        )
    }

    private func makeIsolatedDefaults(suiteName: String) -> UserDefaults {
        let uniqueSuiteName = "\(suiteName).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: uniqueSuiteName) else {
            fatalError("Failed to create isolated defaults suite: \(uniqueSuiteName)")
        }
        defaults.removePersistentDomain(forName: uniqueSuiteName)
        return defaults
    }

    private func makeInMemoryModelContainer() throws -> ModelContainer {
        let schema = Schema([HistoricalDataPoint.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

private enum TestDeleteError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Delete failed."
    }
}
