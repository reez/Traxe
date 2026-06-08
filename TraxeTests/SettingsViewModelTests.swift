import SwiftData
import XCTest

@testable import Traxe

@MainActor
final class SettingsViewModelTests: XCTestCase {
    override func tearDown() {
        SettingsURLProtocolStub.requestHandler = nil
        SettingsURLProtocolStub.capturedRequests = []
        UserDefaults(suiteName: SettingsViewModel.sharedUserDefaultsSuiteName)?
            .removeObject(forKey: "bitaxeIPAddress")
        super.tearDown()
    }

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

    func testTelemetryOnlySettingsFallbackDisablesSettingsWrites() async throws {
        let sharedDefaults = makeIsolatedDefaults(
            suiteName: "SettingsViewModelTests.telemetryFallback"
        )
        sharedDefaults.set("192.0.2.10", forKey: "bitaxeIPAddress")
        let appGroupDefaults = try XCTUnwrap(
            UserDefaults(suiteName: SettingsViewModel.sharedUserDefaultsSuiteName)
        )
        appGroupDefaults.set("192.0.2.10", forKey: "bitaxeIPAddress")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SettingsURLProtocolStub.self]
        let service = NetworkService(session: URLSession(configuration: configuration))
        let payload = try fixtureData(named: "poisoned-optional-settings-system-info.json")
        SettingsURLProtocolStub.requestHandler = { request in
            SettingsURLProtocolStub.capturedRequests.append(request)
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (try XCTUnwrap(response), payload)
        }

        let container = try makeInMemoryModelContainer()
        let viewModel = SettingsViewModel(
            sharedUserDefaults: sharedDefaults,
            networkService: service,
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false
        )

        await viewModel.fetchDeviceSettings()

        XCTAssertTrue(viewModel.isConnected)
        XCTAssertFalse(viewModel.isSettingsConfigurationEditable)
        XCTAssertEqual(viewModel.currentVersion, "future-fw")
        XCTAssertEqual(viewModel.hostname, "future-miner")
        XCTAssertEqual(
            viewModel.settingsConfigurationMessage,
            "Miner settings are unavailable because this firmware returned an unsupported settings format. Metrics are still available, but use the miner web UI to change settings."
        )

        SettingsURLProtocolStub.capturedRequests = []
        let didSavePool = await viewModel.savePoolConfiguration()
        viewModel.hostname = "updated-hostname"
        let didSaveHostname = await viewModel.saveHostnameConfiguration()
        await viewModel.toggleAutoFan()

        XCTAssertFalse(didSavePool)
        XCTAssertFalse(didSaveHostname)
        XCTAssertEqual(viewModel.poolConfigurationError, viewModel.settingsConfigurationMessage)
        XCTAssertEqual(viewModel.hostnameConfigurationError, viewModel.settingsConfigurationMessage)
        XCTAssertTrue(SettingsURLProtocolStub.capturedRequests.isEmpty)
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

    private func fixtureData(named filename: String) throws -> Data {
        let testFile = URL(fileURLWithPath: #filePath)
        let fixtureURL = testFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent(filename)
        return try Data(contentsOf: fixtureURL)
    }
}

private enum TestDeleteError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Delete failed."
    }
}

private final class SettingsURLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var requestHandler:
        ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NetworkError.unknown)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
