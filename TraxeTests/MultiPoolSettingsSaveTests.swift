import SwiftData
import XCTest

@testable import Traxe

@MainActor
final class MultiPoolSettingsSaveTests: XCTestCase {
    override func tearDown() {
        MultiPoolURLProtocolStub.requestHandler = nil
        MultiPoolURLProtocolStub.capturedRequests = []
        UserDefaults(suiteName: SettingsViewModel.sharedUserDefaultsSuiteName)?
            .removeObject(forKey: "bitaxeIPAddress")
        super.tearDown()
    }

    func testEspMiner215SaveSendsPoolsArrayForTheConfiguredSlotIDs() async throws {
        let appGroupDefaults = try XCTUnwrap(
            UserDefaults(suiteName: SettingsViewModel.sharedUserDefaultsSuiteName)
        )
        appGroupDefaults.set("192.0.2.10", forKey: "bitaxeIPAddress")
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent("esp-miner-2-15-0-system-info.json")
        let currentPayload = try Data(contentsOf: fixtureURL)
        let savedPayload = Data(Self.savedMultiPoolPayload.utf8)

        MultiPoolURLProtocolStub.requestHandler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            if request.httpMethod == "PATCH" {
                return (response, Data())
            }
            let didPatch = MultiPoolURLProtocolStub.capturedRequests.contains {
                $0.httpMethod == "PATCH"
            }
            return (response, didPatch ? savedPayload : currentPayload)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultiPoolURLProtocolStub.self]
        let schema = Schema([HistoricalDataPoint.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let viewModel = SettingsViewModel(
            sharedUserDefaults: appGroupDefaults,
            networkService: NetworkService(session: URLSession(configuration: configuration)),
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false
        )

        await viewModel.fetchDeviceSettings()
        XCTAssertFalse(viewModel.supportsPoolModeSettings)
        MultiPoolURLProtocolStub.capturedRequests = []

        viewModel.stratumURL = "solo.ckpool.org"
        viewModel.stratumPortString = "3333"
        viewModel.stratumUser = "bc1qnew.primary"
        viewModel.fallbackStratumURL = "eu.backup.example"
        viewModel.fallbackStratumPortString = "4444"
        viewModel.fallbackStratumUser = "bc1qnew.backup"

        let didSave = await viewModel.savePoolConfiguration()

        XCTAssertTrue(didSave)
        XCTAssertNil(viewModel.poolConfigurationError)
        XCTAssertEqual(
            MultiPoolURLProtocolStub.capturedRequests.map { $0.httpMethod },
            ["GET", "PATCH", "GET"]
        )
        XCTAssertEqual(
            MultiPoolURLProtocolStub.capturedRequests.map { $0.url?.absoluteString },
            [
                "http://192.0.2.10/api/system/info",
                "http://192.0.2.10/api/system",
                "http://192.0.2.10/api/system/info",
            ]
        )

        let patchRequest = try XCTUnwrap(
            MultiPoolURLProtocolStub.capturedRequests.first { $0.httpMethod == "PATCH" }
        )
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(patchRequest.capturedBody))
                as? [String: Any]
        )
        let pools = try XCTUnwrap(body["pools"] as? [[String: Any]])
        XCTAssertEqual(pools.count, 2)
        XCTAssertEqual(pools.compactMap { $0["id"] as? Int }, [2, 3])
        XCTAssertEqual(pools[0]["stratumURL"] as? String, "solo.ckpool.org")
        XCTAssertEqual(pools[0]["stratumPort"] as? Int, 3333)
        XCTAssertEqual(pools[0]["stratumUser"] as? String, "bc1qnew.primary")
        XCTAssertEqual(pools[0]["stratumProtocol"] as? String, "SV1")
        XCTAssertEqual(pools[1]["stratumURL"] as? String, "eu.backup.example")
        XCTAssertEqual(pools[1]["stratumPort"] as? Int, 4444)
        XCTAssertEqual(pools[1]["stratumUser"] as? String, "bc1qnew.backup")
        XCTAssertEqual(pools[1]["stratumProtocol"] as? String, "SV2")
        XCTAssertEqual(
            pools[1]["stratumV2AuthorityPubkey"] as? String,
            "9c4zpyJ2ndm4e8sP2uNc1VNCGxYjqaxWS6wUCjk8zFj6njFquH6"
        )

        // The flat pool properties are no longer registered as writable in v2.15.
        for removedKey in [
            "stratumURL", "stratumPort", "stratumUser", "stratumProtocol",
            "fallbackStratumURL", "fallbackStratumPort", "fallbackStratumUser",
            "stratumV2ChannelType", "stratumV2AuthorityPubkey", "poolMode", "poolBalance",
        ] {
            XCTAssertNil(body[removedKey], "PATCH must not send the obsolete \(removedKey)")
        }
        // Pool indices are not edited by this screen, and the active pool did not change.
        XCTAssertNil(body["primaryPoolIndex"])
        XCTAssertNil(body["secondaryPoolIndex"])
        XCTAssertNil(body["useFallbackStratum"])
    }

    func testEspMiner215SaveSendsActivePoolChangeThenRestartsAndVerifiesIt() async throws {
        let appGroupDefaults = try XCTUnwrap(
            UserDefaults(suiteName: SettingsViewModel.sharedUserDefaultsSuiteName)
        )
        appGroupDefaults.set("192.0.2.10", forKey: "bitaxeIPAddress")
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent("esp-miner-2-15-0-system-info.json")
        let currentPayload = try Data(contentsOf: fixtureURL)
        // The miner applies `useFallbackStratum` while booting, so system info keeps
        // reporting the old value until the restart completed.
        let currentJSON = String(decoding: currentPayload, as: UTF8.self)
        let restartedJSON = currentJSON.replacing(
            "\"useFallbackStratum\": 1",
            with: "\"useFallbackStratum\": 0"
        )
        XCTAssertNotEqual(restartedJSON, currentJSON)
        let restartedPayload = Data(restartedJSON.utf8)

        MultiPoolURLProtocolStub.requestHandler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            guard request.httpMethod == "GET" else {
                return (response, Data())
            }
            let didRestart = MultiPoolURLProtocolStub.capturedRequests.contains {
                $0.url?.path == "/api/system/restart"
            }
            return (response, didRestart ? restartedPayload : currentPayload)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultiPoolURLProtocolStub.self]
        let schema = Schema([HistoricalDataPoint.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let viewModel = SettingsViewModel(
            sharedUserDefaults: appGroupDefaults,
            networkService: NetworkService(session: URLSession(configuration: configuration)),
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false
        )

        await viewModel.fetchDeviceSettings()
        XCTAssertTrue(viewModel.supportsActivePoolSelection)
        XCTAssertTrue(viewModel.useFallbackStratum)
        MultiPoolURLProtocolStub.capturedRequests = []

        viewModel.useFallbackStratum = false

        let didSave = await viewModel.savePoolConfiguration()

        XCTAssertTrue(didSave)
        XCTAssertNil(viewModel.poolConfigurationError)
        XCTAssertFalse(viewModel.isUpdatingPoolConfiguration)
        XCTAssertFalse(viewModel.useFallbackStratum)
        XCTAssertEqual(
            MultiPoolURLProtocolStub.capturedRequests.map { $0.httpMethod },
            ["GET", "PATCH", "GET", "PATCH", "POST", "GET"]
        )
        XCTAssertEqual(
            MultiPoolURLProtocolStub.capturedRequests.map { $0.url?.absoluteString },
            [
                "http://192.0.2.10/api/system/info",
                "http://192.0.2.10/api/system",
                "http://192.0.2.10/api/system/info",
                "http://192.0.2.10/api/system",
                "http://192.0.2.10/api/system/restart",
                "http://192.0.2.10/api/system/info",
            ]
        )

        let patchRequests = MultiPoolURLProtocolStub.capturedRequests.filter {
            $0.httpMethod == "PATCH"
        }
        XCTAssertEqual(patchRequests.count, 2)
        // The pool slots go first, without the flag, so a pool change the miner ignores
        // cannot leave the flag behind in NVS.
        let poolsBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(patchRequests[0].capturedBody))
                as? [String: Any]
        )
        let pools = try XCTUnwrap(poolsBody["pools"] as? [[String: Any]])
        XCTAssertEqual(pools.compactMap { $0["id"] as? Int }, [2, 3])
        XCTAssertNil(poolsBody["useFallbackStratum"])
        XCTAssertNil(poolsBody["primaryPoolIndex"])
        XCTAssertNil(poolsBody["secondaryPoolIndex"])
        // Once the pools are verified the flag is sent on its own, as 0/1 like AxeOS does.
        let activePoolBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(patchRequests[1].capturedBody))
                as? [String: Any]
        )
        XCTAssertEqual(activePoolBody as? [String: Int], ["useFallbackStratum": 0])
    }

    func testEspMiner215SaveDoesNotRestartWhenTheMinerIgnoresThePoolChanges() async throws {
        let appGroupDefaults = try XCTUnwrap(
            UserDefaults(suiteName: SettingsViewModel.sharedUserDefaultsSuiteName)
        )
        appGroupDefaults.set("192.0.2.10", forKey: "bitaxeIPAddress")
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent("esp-miner-2-15-0-system-info.json")
        let unchangedPayload = try Data(contentsOf: fixtureURL)

        MultiPoolURLProtocolStub.requestHandler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, request.httpMethod == "GET" ? unchangedPayload : Data())
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultiPoolURLProtocolStub.self]
        let schema = Schema([HistoricalDataPoint.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let viewModel = SettingsViewModel(
            sharedUserDefaults: appGroupDefaults,
            networkService: NetworkService(session: URLSession(configuration: configuration)),
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false
        )

        await viewModel.fetchDeviceSettings()
        MultiPoolURLProtocolStub.capturedRequests = []
        viewModel.stratumURL = "solo.ckpool.org"
        viewModel.stratumUser = "bc1qnew.primary"
        viewModel.useFallbackStratum = false

        let didSave = await viewModel.savePoolConfiguration()

        XCTAssertFalse(didSave)
        XCTAssertEqual(
            viewModel.poolConfigurationError,
            "The miner accepted the request but did not apply the pool settings. Please try again, or change the pool from the miner web UI."
        )
        // The readback shows the pool change was not applied, so Traxe reports the failure,
        // never sends the active pool, and does not restart. Nothing is left on the miner.
        XCTAssertEqual(
            MultiPoolURLProtocolStub.capturedRequests.map { $0.httpMethod },
            ["GET", "PATCH", "GET"]
        )
        let patchRequest = try XCTUnwrap(
            MultiPoolURLProtocolStub.capturedRequests.first { $0.httpMethod == "PATCH" }
        )
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(patchRequest.capturedBody))
                as? [String: Any]
        )
        XCTAssertNotNil(body["pools"])
        XCTAssertNil(body["useFallbackStratum"])
        // The screen shows the selection the miner still reports.
        XCTAssertTrue(viewModel.useFallbackStratum)
    }

    func testEspMiner215SaveRefusesFallbackActivePoolWithoutAFallbackPool() async throws {
        let appGroupDefaults = try XCTUnwrap(
            UserDefaults(suiteName: SettingsViewModel.sharedUserDefaultsSuiteName)
        )
        appGroupDefaults.set("192.0.2.10", forKey: "bitaxeIPAddress")
        // Only the primary slot exists on the miner; the fallback slot 3 was never created.
        let currentJSON = """
            {
              "hostname": "bitaxe-215",
              "version": "v2.15.0",
              "primaryPoolIndex": 2,
              "secondaryPoolIndex": 3,
              "useFallbackStratum": 0,
              "pools": [
                {
                  "id": 2,
                  "stratumProtocol": "SV1",
                  "stratumURL": "public-pool.io",
                  "stratumPort": 21496,
                  "stratumUser": "bc1qexample.primary",
                  "stratumPassword": "*****",
                  "stratumV2ChannelType": "extended",
                  "stratumV2AuthorityPubkey": ""
                }
              ],
              "stratumURL": "public-pool.io",
              "stratumPort": 21496,
              "stratumUser": "bc1qexample.primary",
              "stratumProtocol": "SV1",
              "stratumV2ChannelType": "extended",
              "stratumV2AuthorityPubkey": "",
              "fallbackStratumURL": "",
              "fallbackStratumPort": 3333,
              "fallbackStratumUser": "",
              "fallbackStratumProtocol": "SV1",
              "fallbackStratumV2ChannelType": "extended",
              "fallbackStratumV2AuthorityPubkey": ""
            }
            """
        let currentPayload = Data(currentJSON.utf8)

        MultiPoolURLProtocolStub.requestHandler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, request.httpMethod == "GET" ? currentPayload : Data())
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultiPoolURLProtocolStub.self]
        let schema = Schema([HistoricalDataPoint.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let viewModel = SettingsViewModel(
            sharedUserDefaults: appGroupDefaults,
            networkService: NetworkService(session: URLSession(configuration: configuration)),
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false
        )

        await viewModel.fetchDeviceSettings()
        XCTAssertTrue(viewModel.supportsActivePoolSelection)
        XCTAssertFalse(viewModel.useFallbackStratum)
        MultiPoolURLProtocolStub.capturedRequests = []
        // A host alone does not make a pool; the plan drops this incomplete new slot.
        viewModel.fallbackStratumURL = "eu.backup.example"
        viewModel.fallbackStratumPortString = ""
        viewModel.fallbackStratumUser = ""
        viewModel.useFallbackStratum = true

        let didSave = await viewModel.savePoolConfiguration()

        XCTAssertFalse(didSave)
        XCTAssertEqual(
            viewModel.poolConfigurationError,
            "Enter the fallback pool host, port and user before selecting it as the active pool."
        )
        XCTAssertFalse(viewModel.isUpdatingPoolConfiguration)
        // Nothing may be written: the flag alone would make the miner boot onto an empty slot.
        XCTAssertEqual(
            MultiPoolURLProtocolStub.capturedRequests.map { $0.httpMethod },
            ["GET"]
        )
    }

    func testEspMiner215SaveReportsSavedActivePoolWhenRestartRequestFails() async throws {
        let appGroupDefaults = try XCTUnwrap(
            UserDefaults(suiteName: SettingsViewModel.sharedUserDefaultsSuiteName)
        )
        appGroupDefaults.set("192.0.2.10", forKey: "bitaxeIPAddress")
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent("esp-miner-2-15-0-system-info.json")
        let currentPayload = try Data(contentsOf: fixtureURL)

        MultiPoolURLProtocolStub.requestHandler = { request in
            let isRestart = request.url?.path == "/api/system/restart"
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: isRestart ? 500 : 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, request.httpMethod == "GET" ? currentPayload : Data())
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultiPoolURLProtocolStub.self]
        let schema = Schema([HistoricalDataPoint.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let viewModel = SettingsViewModel(
            sharedUserDefaults: appGroupDefaults,
            networkService: NetworkService(session: URLSession(configuration: configuration)),
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false
        )

        await viewModel.fetchDeviceSettings()
        XCTAssertTrue(viewModel.useFallbackStratum)
        MultiPoolURLProtocolStub.capturedRequests = []
        viewModel.useFallbackStratum = false

        let didSave = await viewModel.savePoolConfiguration()

        XCTAssertFalse(didSave)
        XCTAssertEqual(
            viewModel.poolConfigurationError,
            "The active pool was saved but the miner could not be restarted. Restart the miner to apply the change."
        )
        XCTAssertFalse(viewModel.isUpdatingPoolConfiguration)
        // The flag PATCH went through, so the failure is reported as a restart problem and
        // there is no readback poll.
        XCTAssertEqual(
            MultiPoolURLProtocolStub.capturedRequests.map { $0.httpMethod },
            ["GET", "PATCH", "GET", "PATCH", "POST"]
        )
        // The miner still reports its boot-time value, and so does the screen; picking
        // Fallback again then differs from it and resends.
        XCTAssertTrue(viewModel.useFallbackStratum)
    }

    func testEspMiner215SavePreservesMaskedPasswordAndUntouchedPoolProperties() async throws {
        let appGroupDefaults = try XCTUnwrap(
            UserDefaults(suiteName: SettingsViewModel.sharedUserDefaultsSuiteName)
        )
        appGroupDefaults.set("192.0.2.10", forKey: "bitaxeIPAddress")
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent("esp-miner-2-15-0-system-info.json")
        let currentPayload = try Data(contentsOf: fixtureURL)
        let savedPayload = Data(Self.savedMultiPoolPayload.utf8)

        MultiPoolURLProtocolStub.requestHandler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            if request.httpMethod == "PATCH" {
                return (response, Data())
            }
            let didPatch = MultiPoolURLProtocolStub.capturedRequests.contains {
                $0.httpMethod == "PATCH"
            }
            return (response, didPatch ? savedPayload : currentPayload)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultiPoolURLProtocolStub.self]
        let schema = Schema([HistoricalDataPoint.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let viewModel = SettingsViewModel(
            sharedUserDefaults: appGroupDefaults,
            networkService: NetworkService(session: URLSession(configuration: configuration)),
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false
        )

        await viewModel.fetchDeviceSettings()
        viewModel.stratumURL = "solo.ckpool.org"
        viewModel.stratumPortString = "3333"
        viewModel.stratumUser = "bc1qnew.primary"
        viewModel.fallbackStratumURL = "eu.backup.example"
        viewModel.fallbackStratumPortString = "4444"
        viewModel.fallbackStratumUser = "bc1qnew.backup"

        _ = await viewModel.savePoolConfiguration()

        let patchRequest = try XCTUnwrap(
            MultiPoolURLProtocolStub.capturedRequests.first { $0.httpMethod == "PATCH" }
        )
        let bodyData = try XCTUnwrap(patchRequest.capturedBody)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )
        let pools = try XCTUnwrap(body["pools"] as? [[String: Any]])
        XCTAssertEqual(pools.count, 2, "Pool slots the user did not edit must stay untouched")

        // Submitting the mask keeps the password stored on the miner.
        XCTAssertEqual(pools[0]["stratumPassword"] as? String, "*****")
        XCTAssertEqual(pools[1]["stratumPassword"] as? String, "*****")
        XCTAssertEqual(pools[0]["stratumCert"] as? String, "-----BEGIN CERTIFICATE-----")
        XCTAssertEqual(pools[0]["stratumSuggestedDifficulty"] as? Int, 512)

        // Omitted pool properties are reset to firmware defaults, so the untouched ones have
        // to be echoed back with their original JSON value types.
        let bodyString = try XCTUnwrap(String(data: bodyData, encoding: .utf8))
        XCTAssertTrue(bodyString.contains("\"stratumTLS\":1"))
        XCTAssertTrue(bodyString.contains("\"stratumExtranonceSubscribe\":true"))
        XCTAssertTrue(bodyString.contains("\"stratumExtranonceSubscribe\":false"))
        XCTAssertTrue(bodyString.contains("\"stratumDecodeCoinbase\":false"))
        XCTAssertTrue(bodyString.contains("\"stratumV2RequireAuth\":true"))
        XCTAssertTrue(bodyString.contains("\"nested\":[1,true,null]"))
    }

    func testEspMiner215SaveReportsFailureWhenTheMinerIgnoresThePoolChanges() async throws {
        let appGroupDefaults = try XCTUnwrap(
            UserDefaults(suiteName: SettingsViewModel.sharedUserDefaultsSuiteName)
        )
        appGroupDefaults.set("192.0.2.10", forKey: "bitaxeIPAddress")
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent("esp-miner-2-15-0-system-info.json")
        let unchangedPayload = try Data(contentsOf: fixtureURL)

        MultiPoolURLProtocolStub.requestHandler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, request.httpMethod == "PATCH" ? Data() : unchangedPayload)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultiPoolURLProtocolStub.self]
        let schema = Schema([HistoricalDataPoint.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let viewModel = SettingsViewModel(
            sharedUserDefaults: appGroupDefaults,
            networkService: NetworkService(session: URLSession(configuration: configuration)),
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false
        )

        await viewModel.fetchDeviceSettings()
        MultiPoolURLProtocolStub.capturedRequests = []
        viewModel.stratumURL = "solo.ckpool.org"
        viewModel.stratumUser = "bc1qnew.primary"

        let didSave = await viewModel.savePoolConfiguration()

        XCTAssertFalse(didSave)
        XCTAssertEqual(
            viewModel.poolConfigurationError,
            "The miner accepted the request but did not apply the pool settings. Please try again, or change the pool from the miner web UI."
        )
        XCTAssertFalse(viewModel.isUpdatingPoolConfiguration)
        XCTAssertEqual(
            MultiPoolURLProtocolStub.capturedRequests.map { $0.httpMethod },
            ["GET", "PATCH", "GET"]
        )
    }

    func testLegacyFirmwareWithoutPoolsKeepsSendingTheFlatPoolPatch() async throws {
        let appGroupDefaults = try XCTUnwrap(
            UserDefaults(suiteName: SettingsViewModel.sharedUserDefaultsSuiteName)
        )
        appGroupDefaults.set("192.0.2.10", forKey: "bitaxeIPAddress")
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent("esp-miner-string-system-info.json")
        let payload = try Data(contentsOf: fixtureURL)

        MultiPoolURLProtocolStub.requestHandler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, request.httpMethod == "GET" ? payload : Data())
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultiPoolURLProtocolStub.self]
        let schema = Schema([HistoricalDataPoint.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let viewModel = SettingsViewModel(
            sharedUserDefaults: appGroupDefaults,
            networkService: NetworkService(session: URLSession(configuration: configuration)),
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false
        )

        await viewModel.fetchDeviceSettings()
        XCTAssertFalse(viewModel.supportsPoolModeSettings)
        MultiPoolURLProtocolStub.capturedRequests = []
        viewModel.stratumURL = "solo.ckpool.org"
        viewModel.stratumPortString = "3333"
        viewModel.stratumUser = "bc1qnew.primary"
        viewModel.fallbackStratumURL = "eu.backup.example"
        viewModel.fallbackStratumPortString = "4444"
        viewModel.fallbackStratumUser = "bc1qnew.backup"
        viewModel.stratumV2AuthorityPubkey = ""
        viewModel.fallbackStratumV2AuthorityPubkey = ""

        let didSave = await viewModel.savePoolConfiguration()

        XCTAssertTrue(didSave)
        XCTAssertFalse(
            MultiPoolURLProtocolStub.capturedRequests.contains {
                $0.url?.absoluteString == "http://192.0.2.10/api/system/restart"
            },
            "ESP-Miner reports no pool mode, so a restart must not be forced"
        )
        let patchRequests = MultiPoolURLProtocolStub.capturedRequests.filter {
            $0.httpMethod == "PATCH"
        }
        XCTAssertEqual(patchRequests.count, 1)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(patchRequests[0].capturedBody))
                as? [String: Any]
        )
        XCTAssertNil(body["pools"])
        XCTAssertEqual(body["stratumURL"] as? String, "solo.ckpool.org")
        XCTAssertEqual(body["stratumPort"] as? Int, 3333)
        XCTAssertEqual(body["stratumUser"] as? String, "bc1qnew.primary")
        XCTAssertEqual(body["fallbackStratumURL"] as? String, "eu.backup.example")
        XCTAssertEqual(body["fallbackStratumPort"] as? Int, 4444)
        XCTAssertEqual(body["fallbackStratumUser"] as? String, "bc1qnew.backup")
        XCTAssertEqual(body["stratumProtocol"] as? String, "SV2")
        XCTAssertEqual(body["fallbackStratumProtocol"] as? String, "SV1")
        XCTAssertEqual(body["stratumV2ChannelType"] as? String, "extended")
        XCTAssertEqual(body["fallbackStratumV2ChannelType"] as? String, "standard")
        XCTAssertEqual(body["stratumV2AuthorityPubkey"] as? String, "")
        XCTAssertNil(body["poolMode"])
        XCTAssertNil(body["poolBalance"])
    }

    func testNerdQaxePoolModeAndBalanceStillUseTheFlatPatchWithoutRestart() async throws {
        let appGroupDefaults = try XCTUnwrap(
            UserDefaults(suiteName: SettingsViewModel.sharedUserDefaultsSuiteName)
        )
        appGroupDefaults.set("192.0.2.10", forKey: "bitaxeIPAddress")
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent("nerdqaxe-v1-0-37-2-lts-system-info.json")
        let payload = try Data(contentsOf: fixtureURL)

        MultiPoolURLProtocolStub.requestHandler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, request.httpMethod == "GET" ? payload : Data())
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultiPoolURLProtocolStub.self]
        let schema = Schema([HistoricalDataPoint.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let viewModel = SettingsViewModel(
            sharedUserDefaults: appGroupDefaults,
            networkService: NetworkService(session: URLSession(configuration: configuration)),
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false
        )

        await viewModel.fetchDeviceSettings()
        XCTAssertTrue(viewModel.supportsPoolModeSettings)
        XCTAssertEqual(viewModel.poolMode, 1)
        XCTAssertTrue(viewModel.isDualPool)
        MultiPoolURLProtocolStub.capturedRequests = []
        viewModel.poolBalance = 70
        viewModel.stratumV2AuthorityPubkey = ""
        viewModel.fallbackStratumV2AuthorityPubkey = ""

        let didSave = await viewModel.savePoolConfiguration()

        XCTAssertTrue(didSave)
        XCTAssertFalse(
            MultiPoolURLProtocolStub.capturedRequests.contains {
                $0.url?.absoluteString == "http://192.0.2.10/api/system/restart"
            },
            "The miner already reports the requested pool mode, so it must not be restarted"
        )
        let patchRequests = MultiPoolURLProtocolStub.capturedRequests.filter {
            $0.httpMethod == "PATCH"
        }
        XCTAssertEqual(patchRequests.count, 1)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(patchRequests[0].capturedBody))
                as? [String: Any]
        )
        XCTAssertNil(body["pools"])
        XCTAssertEqual(body["poolMode"] as? Int, 1)
        XCTAssertEqual(body["poolBalance"] as? Int, 70)
        XCTAssertEqual(body["stratumURL"] as? String, "new.nerd.pool.example")
        XCTAssertEqual(body["fallbackStratumURL"] as? String, "new.nerd.backup.example")
    }

    func testFanAndHostnameWritesDoNotUseTheMultiPoolRequests() async throws {
        let appGroupDefaults = try XCTUnwrap(
            UserDefaults(suiteName: SettingsViewModel.sharedUserDefaultsSuiteName)
        )
        appGroupDefaults.set("192.0.2.10", forKey: "bitaxeIPAddress")
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent("esp-miner-2-15-0-system-info.json")
        let payload = try Data(contentsOf: fixtureURL)

        MultiPoolURLProtocolStub.requestHandler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, request.httpMethod == "GET" ? payload : Data())
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultiPoolURLProtocolStub.self]
        let schema = Schema([HistoricalDataPoint.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let viewModel = SettingsViewModel(
            sharedUserDefaults: appGroupDefaults,
            networkService: NetworkService(session: URLSession(configuration: configuration)),
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false
        )

        await viewModel.fetchDeviceSettings()
        MultiPoolURLProtocolStub.capturedRequests = []

        await viewModel.toggleAutoFan()

        XCTAssertEqual(MultiPoolURLProtocolStub.capturedRequests.map { $0.httpMethod }, ["PATCH"])
        let fanBody = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try XCTUnwrap(MultiPoolURLProtocolStub.capturedRequests[0].capturedBody)
            ) as? [String: Any]
        )
        XCTAssertEqual(fanBody as? [String: Int], ["autofanspeed": 0])

        MultiPoolURLProtocolStub.capturedRequests = []
        viewModel.hostname = "bitaxe-renamed"
        let didSaveHostname = await viewModel.saveHostnameConfiguration()

        XCTAssertTrue(didSaveHostname)
        XCTAssertEqual(
            MultiPoolURLProtocolStub.capturedRequests.map { $0.httpMethod },
            ["PATCH", "GET"]
        )
        let hostnameBody = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try XCTUnwrap(MultiPoolURLProtocolStub.capturedRequests[0].capturedBody)
            ) as? [String: Any]
        )
        XCTAssertEqual(hostnameBody as? [String: String], ["hostname": "bitaxe-renamed"])
    }

    func testEspMiner215SaveSkipsAPoolSlotTheMinerHasNotConfigured() async throws {
        let appGroupDefaults = try XCTUnwrap(
            UserDefaults(suiteName: SettingsViewModel.sharedUserDefaultsSuiteName)
        )
        appGroupDefaults.set("192.0.2.10", forKey: "bitaxeIPAddress")
        let currentJSON = """
            {
              "hostname": "bitaxe-215",
              "version": "v2.15.0",
              "primaryPoolIndex": 2,
              "secondaryPoolIndex": 3,
              "useFallbackStratum": 0,
              "pools": [
                {
                  "id": 2,
                  "stratumProtocol": "SV1",
                  "stratumURL": "public-pool.io",
                  "stratumPort": 21496,
                  "stratumUser": "bc1qexample.primary",
                  "stratumPassword": "*****",
                  "stratumV2ChannelType": "extended",
                  "stratumV2AuthorityPubkey": ""
                }
              ],
              "stratumURL": "public-pool.io",
              "stratumPort": 21496,
              "stratumUser": "bc1qexample.primary",
              "stratumProtocol": "SV1",
              "stratumV2ChannelType": "extended",
              "stratumV2AuthorityPubkey": "",
              "fallbackStratumURL": "",
              "fallbackStratumPort": 3333,
              "fallbackStratumUser": "",
              "fallbackStratumProtocol": "SV1",
              "fallbackStratumV2ChannelType": "extended",
              "fallbackStratumV2AuthorityPubkey": ""
            }
            """
        let currentPayload = Data(currentJSON.utf8)
        let savedPayload = Data(
            currentJSON
                .replacingOccurrences(of: "public-pool.io", with: "solo.ckpool.org")
                .replacingOccurrences(of: "bc1qexample.primary", with: "bc1qnew.primary")
                .utf8
        )

        MultiPoolURLProtocolStub.requestHandler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            if request.httpMethod == "PATCH" {
                return (response, Data())
            }
            let didPatch = MultiPoolURLProtocolStub.capturedRequests.contains {
                $0.httpMethod == "PATCH"
            }
            return (response, didPatch ? savedPayload : currentPayload)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultiPoolURLProtocolStub.self]
        let schema = Schema([HistoricalDataPoint.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let viewModel = SettingsViewModel(
            sharedUserDefaults: appGroupDefaults,
            networkService: NetworkService(session: URLSession(configuration: configuration)),
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false
        )

        await viewModel.fetchDeviceSettings()
        XCTAssertEqual(viewModel.fallbackStratumURL, "")
        XCTAssertEqual(viewModel.fallbackStratumUser, "")
        MultiPoolURLProtocolStub.capturedRequests = []
        viewModel.stratumURL = "solo.ckpool.org"
        viewModel.stratumUser = "bc1qnew.primary"

        let didSave = await viewModel.savePoolConfiguration()

        XCTAssertTrue(didSave, "An empty fallback slot must not fail the primary pool save")
        XCTAssertNil(viewModel.poolConfigurationError)
        let patchRequest = try XCTUnwrap(
            MultiPoolURLProtocolStub.capturedRequests.first { $0.httpMethod == "PATCH" }
        )
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(patchRequest.capturedBody))
                as? [String: Any]
        )
        let pools = try XCTUnwrap(body["pools"] as? [[String: Any]])
        XCTAssertEqual(pools.count, 1)
        XCTAssertEqual(pools[0]["id"] as? Int, 2)
        XCTAssertEqual(pools[0]["stratumURL"] as? String, "solo.ckpool.org")
    }

    func testAdjustFanSpeedSendsTheManualSpeedUnderBothFirmwareKeys() async throws {
        let appGroupDefaults = try XCTUnwrap(
            UserDefaults(suiteName: SettingsViewModel.sharedUserDefaultsSuiteName)
        )
        appGroupDefaults.set("192.0.2.10", forKey: "bitaxeIPAddress")
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent("esp-miner-string-system-info.json")
        let payload = try Data(contentsOf: fixtureURL)

        MultiPoolURLProtocolStub.requestHandler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, request.httpMethod == "GET" ? payload : Data())
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultiPoolURLProtocolStub.self]
        let schema = Schema([HistoricalDataPoint.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let viewModel = SettingsViewModel(
            sharedUserDefaults: appGroupDefaults,
            networkService: NetworkService(session: URLSession(configuration: configuration)),
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false
        )

        await viewModel.fetchDeviceSettings()
        XCTAssertEqual(viewModel.fanSpeed, 75)
        viewModel.isAutoFan = false
        MultiPoolURLProtocolStub.capturedRequests = []

        await viewModel.adjustFanSpeed(by: 5)

        XCTAssertEqual(viewModel.fanSpeed, 80)
        XCTAssertEqual(MultiPoolURLProtocolStub.capturedRequests.map { $0.httpMethod }, ["PATCH"])
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try XCTUnwrap(MultiPoolURLProtocolStub.capturedRequests[0].capturedBody)
            ) as? [String: Any]
        )
        // ESP-Miner 2.10 and earlier read `fanspeed`; 2.11 and later read `manualFanSpeed`.
        XCTAssertEqual(body as? [String: Int], ["fanspeed": 80, "manualFanSpeed": 80])
    }

    func testLegacyEspMinerPoolSaveAsksForARestartOnlyWhenThePoolChanged() async throws {
        let appGroupDefaults = try XCTUnwrap(
            UserDefaults(suiteName: SettingsViewModel.sharedUserDefaultsSuiteName)
        )
        appGroupDefaults.set("192.0.2.10", forKey: "bitaxeIPAddress")
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent("esp-miner-string-system-info.json")
        // The fixture's placeholder SV2 pubkeys fail validation on save. A miner that reports
        // valid ones lets the first save resend exactly what it reported.
        let validAuthorityPubkey = "9c4zpyJ2ndm4e8sP2uNc1VNCGxYjqaxWS6wUCjk8zFj6njFquH6"
        let payload = Data(
            try String(contentsOf: fixtureURL, encoding: .utf8)
                .replacing("primaryAuthorityPubkey", with: validAuthorityPubkey)
                .replacing("fallbackAuthorityPubkey", with: validAuthorityPubkey)
                .utf8
        )

        MultiPoolURLProtocolStub.requestHandler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, request.httpMethod == "GET" ? payload : Data())
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultiPoolURLProtocolStub.self]
        let schema = Schema([HistoricalDataPoint.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let viewModel = SettingsViewModel(
            sharedUserDefaults: appGroupDefaults,
            networkService: NetworkService(session: URLSession(configuration: configuration)),
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false
        )

        await viewModel.fetchDeviceSettings()
        XCTAssertFalse(viewModel.supportsPoolModeSettings)
        XCTAssertFalse(viewModel.needsRestartToApplySettings)

        // Saving exactly what the miner reports changes nothing, so no restart is needed.
        var didSave = await viewModel.savePoolConfiguration()

        XCTAssertTrue(didSave)
        XCTAssertFalse(viewModel.needsRestartToApplySettings)

        MultiPoolURLProtocolStub.capturedRequests = []
        viewModel.stratumURL = "solo.ckpool.org"
        didSave = await viewModel.savePoolConfiguration()

        XCTAssertTrue(didSave)
        XCTAssertTrue(
            viewModel.needsRestartToApplySettings,
            "ESP-Miner before 2.15 applies a changed pool only after a restart"
        )
        XCTAssertFalse(
            MultiPoolURLProtocolStub.capturedRequests.contains {
                $0.url?.absoluteString == "http://192.0.2.10/api/system/restart"
            },
            "The restart is offered to the user, not forced"
        )
    }

    func testNerdQaxePoolSaveDoesNotAskForARestartButAHostnameChangeDoes() async throws {
        let appGroupDefaults = try XCTUnwrap(
            UserDefaults(suiteName: SettingsViewModel.sharedUserDefaultsSuiteName)
        )
        appGroupDefaults.set("192.0.2.10", forKey: "bitaxeIPAddress")
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent("nerdqaxe-v1-0-37-2-lts-system-info.json")
        let payload = try Data(contentsOf: fixtureURL)

        MultiPoolURLProtocolStub.requestHandler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, request.httpMethod == "GET" ? payload : Data())
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultiPoolURLProtocolStub.self]
        let schema = Schema([HistoricalDataPoint.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let viewModel = SettingsViewModel(
            sharedUserDefaults: appGroupDefaults,
            networkService: NetworkService(session: URLSession(configuration: configuration)),
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false
        )

        await viewModel.fetchDeviceSettings()
        XCTAssertTrue(viewModel.supportsPoolModeSettings)
        viewModel.stratumURL = "solo.ckpool.org"
        viewModel.stratumV2AuthorityPubkey = ""
        viewModel.fallbackStratumV2AuthorityPubkey = ""

        let didSavePool = await viewModel.savePoolConfiguration()

        XCTAssertTrue(didSavePool)
        XCTAssertFalse(
            viewModel.needsRestartToApplySettings,
            "NerdQAxe reconnects to a changed pool on its own"
        )

        viewModel.hostname = "nerdqaxe-renamed"
        let didSaveHostname = await viewModel.saveHostnameConfiguration()

        XCTAssertTrue(didSaveHostname)
        XCTAssertTrue(
            viewModel.needsRestartToApplySettings,
            "NerdQAxe reads a saved hostname only while booting"
        )

        // The reload after the save put the miner's reported hostname back in the field.
        let didSaveSameHostname = await viewModel.saveHostnameConfiguration()

        XCTAssertTrue(didSaveSameHostname)
        XCTAssertFalse(
            viewModel.needsRestartToApplySettings,
            "An unchanged hostname needs no restart"
        )
    }

    func testEspMinerHostnameSaveAsksForARestartOnlyWhenTheHostnameChanged() async throws {
        let appGroupDefaults = try XCTUnwrap(
            UserDefaults(suiteName: SettingsViewModel.sharedUserDefaultsSuiteName)
        )
        appGroupDefaults.set("192.0.2.10", forKey: "bitaxeIPAddress")
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent("esp-miner-2-15-0-system-info.json")
        let payload = try Data(contentsOf: fixtureURL)

        MultiPoolURLProtocolStub.requestHandler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, request.httpMethod == "GET" ? payload : Data())
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultiPoolURLProtocolStub.self]
        let schema = Schema([HistoricalDataPoint.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let viewModel = SettingsViewModel(
            sharedUserDefaults: appGroupDefaults,
            networkService: NetworkService(session: URLSession(configuration: configuration)),
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false
        )

        await viewModel.fetchDeviceSettings()
        XCTAssertEqual(viewModel.hostname, "bitaxe-215")

        var didSave = await viewModel.saveHostnameConfiguration()

        XCTAssertTrue(didSave)
        XCTAssertFalse(viewModel.needsRestartToApplySettings)

        viewModel.hostname = "bitaxe-renamed"
        didSave = await viewModel.saveHostnameConfiguration()

        XCTAssertTrue(didSave)
        XCTAssertTrue(
            viewModel.needsRestartToApplySettings,
            "ESP-Miner applies a hostname while booting"
        )
    }

    func testPoolCatalogDraftMirrorsTheMinerSlotsAndAddsBlankSelectedSlots() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent("esp-miner-2-15-0-system-info.json")
        let payload = try Data(contentsOf: fixtureURL)
        let systemInfo = try JSONDecoder().decode(SystemInfoDTO.self, from: payload)

        let draft = PoolCatalogDraft(systemInfo: systemInfo)

        XCTAssertEqual(draft.slots.map(\.id), [0, 2, 3])
        XCTAssertEqual(draft.primaryPoolID, 2)
        XCTAssertEqual(draft.secondaryPoolID, 3)
        XCTAssertTrue(draft.useFallbackStratum)
        XCTAssertEqual(draft.nextFreeSlotID, 1)
        let backup = try XCTUnwrap(draft.slot(withID: 3))
        XCTAssertEqual(backup.title, "Pool 4")
        XCTAssertEqual(backup.menuLabel, "Pool 4 · backup.pool.example")
        XCTAssertEqual(backup.stratumPortString, "4333")
        XCTAssertEqual(backup.stratumProtocol, "SV2")
        XCTAssertEqual(backup.stratumV2ChannelType, "standard")
        XCTAssertEqual(
            backup.stratumV2AuthorityPubkey,
            "9c4zpyJ2ndm4e8sP2uNc1VNCGxYjqaxWS6wUCjk8zFj6njFquH6"
        )
        XCTAssertNil(PoolCatalogSavePlan.validationError(for: draft))

        // A selected slot the miner has not configured shows up blank, the way AxeOS lists it.
        let fallbackMissingJSON = String(decoding: payload, as: UTF8.self).replacing(
            "\"secondaryPoolIndex\": 3",
            with: "\"secondaryPoolIndex\": 5"
        )
        let fallbackMissingInfo = try JSONDecoder().decode(
            SystemInfoDTO.self,
            from: Data(fallbackMissingJSON.utf8)
        )
        let fallbackMissingDraft = PoolCatalogDraft(systemInfo: fallbackMissingInfo)
        XCTAssertEqual(fallbackMissingDraft.slots.map(\.id), [0, 2, 3, 5])
        let blankSlot = try XCTUnwrap(fallbackMissingDraft.slot(withID: 5))
        XCTAssertTrue(blankSlot.isBlank)
        XCTAssertEqual(blankSlot.menuLabel, "Pool 6 · New Pool")
        // The miner is held on the fallback, so the blank fallback slot blocks saving.
        XCTAssertEqual(
            PoolCatalogSavePlan.validationError(for: fallbackMissingDraft),
            "Fill in Pool 6 before selecting the fallback as the active pool."
        )
    }

    func testPoolCatalogValidationRejectsIncompleteSlotsAndDuplicateSelection() throws {
        var publicPool = PoolSlotDraft(id: 0)
        publicPool.stratumURL = "public-pool.io"
        publicPool.stratumPortString = "3333"
        publicPool.stratumUser = "bc1qexample.primary"
        var backup = PoolSlotDraft(id: 1)
        backup.stratumURL = "solo.ckpool.org"
        backup.stratumPortString = "3333"
        backup.stratumUser = "bc1qexample.backup"
        var draft = PoolCatalogDraft(
            slots: [publicPool, backup],
            primaryPoolID: 0,
            secondaryPoolID: 1,
            useFallbackStratum: false
        )
        XCTAssertNil(PoolCatalogSavePlan.validationError(for: draft))

        let added = try XCTUnwrap(draft.addSlot())
        XCTAssertEqual(added.id, 2)
        draft.slots[2].stratumURL = "mine.ocean.xyz"
        XCTAssertEqual(
            PoolCatalogSavePlan.validationError(for: draft),
            "Pool 3 needs a host, a port between 1 and 65535, and a user."
        )
        draft.slots[2].stratumPortString = "3334"
        draft.slots[2].stratumUser = "bc1qexample.ocean"
        XCTAssertNil(PoolCatalogSavePlan.validationError(for: draft))

        draft.slots[2].stratumURL = "stratum+tcp://mine.ocean.xyz"
        XCTAssertEqual(
            PoolCatalogSavePlan.validationError(for: draft),
            "Pool 3 host must not include 'stratum+tcp://' or a port."
        )
        draft.slots[2].stratumURL = "mine.ocean.xyz"

        draft.secondaryPoolID = 0
        XCTAssertEqual(
            PoolCatalogSavePlan.validationError(for: draft),
            "The primary and fallback must be different pools."
        )
        draft.secondaryPoolID = 1

        // Selected slots cannot be removed; spare ones can, and come back on demand.
        XCTAssertFalse(draft.deleteSlot(withID: 0))
        XCTAssertFalse(draft.deleteSlot(withID: 1))
        XCTAssertTrue(draft.deleteSlot(withID: 2))
        XCTAssertEqual(draft.slots.map(\.id), [0, 1])
        XCTAssertEqual(draft.deletedPoolIDs, [2])
        XCTAssertEqual(draft.addSlot()?.id, 2)
        XCTAssertEqual(draft.deletedPoolIDs, [])
    }

    func testPoolCatalogSaveWritesSlotsThenSelectionThenDeletesThenRestarts() async throws {
        let appGroupDefaults = try XCTUnwrap(
            UserDefaults(suiteName: SettingsViewModel.sharedUserDefaultsSuiteName)
        )
        appGroupDefaults.set("192.0.2.10", forKey: "bitaxeIPAddress")
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent("esp-miner-2-15-0-system-info.json")
        let currentPayload = try Data(contentsOf: fixtureURL)

        // After the pools PATCH the miner reports the new slot 1; after the restart it also
        // reports the moved primary and the cleared slot 0.
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: currentPayload) as? [String: Any]
        )
        var pools = try XCTUnwrap(json["pools"] as? [[String: Any]])
        pools.append([
            "id": 1,
            "stratumProtocol": "SV1",
            "stratumURL": "solo.ckpool.org",
            "stratumPort": 3333,
            "stratumUser": "bc1qnew.primary",
            "stratumPassword": "*****",
            "stratumV2ChannelType": "standard",
            "stratumV2AuthorityPubkey": "",
        ])
        json["pools"] = pools
        let slotAddedPayload = try JSONSerialization.data(withJSONObject: json)
        json["primaryPoolIndex"] = 1
        json["pools"] = pools.filter { ($0["id"] as? Int) != 0 }
        let restartedPayload = try JSONSerialization.data(withJSONObject: json)

        MultiPoolURLProtocolStub.requestHandler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            guard request.httpMethod == "GET" else {
                return (response, Data())
            }
            let captured = MultiPoolURLProtocolStub.capturedRequests
            if captured.contains(where: { $0.url?.path == "/api/system/restart" }) {
                return (response, restartedPayload)
            }
            if captured.contains(where: { $0.httpMethod == "PATCH" }) {
                return (response, slotAddedPayload)
            }
            return (response, currentPayload)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultiPoolURLProtocolStub.self]
        let schema = Schema([HistoricalDataPoint.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let viewModel = SettingsViewModel(
            sharedUserDefaults: appGroupDefaults,
            networkService: NetworkService(session: URLSession(configuration: configuration)),
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false
        )

        await viewModel.fetchDeviceSettings()
        XCTAssertTrue(viewModel.supportsMultiPoolSettings)
        var draft = try XCTUnwrap(viewModel.poolCatalog)
        MultiPoolURLProtocolStub.capturedRequests = []

        let added = try XCTUnwrap(draft.addSlot())
        XCTAssertEqual(added.id, 1)
        let addedIndex = try XCTUnwrap(draft.slots.firstIndex { $0.id == 1 })
        draft.slots[addedIndex].stratumURL = "solo.ckpool.org"
        draft.slots[addedIndex].stratumPortString = "3333"
        draft.slots[addedIndex].stratumUser = "bc1qnew.primary"
        draft.primaryPoolID = 1
        XCTAssertTrue(draft.deleteSlot(withID: 0))

        let didSave = await viewModel.savePoolCatalog(draft)

        XCTAssertTrue(didSave)
        XCTAssertNil(viewModel.poolConfigurationError)
        XCTAssertFalse(viewModel.isUpdatingPoolConfiguration)
        XCTAssertEqual(
            MultiPoolURLProtocolStub.capturedRequests.map { $0.httpMethod },
            ["GET", "PATCH", "GET", "PATCH", "DELETE", "POST", "GET"]
        )
        XCTAssertEqual(
            MultiPoolURLProtocolStub.capturedRequests.map { $0.url?.absoluteString },
            [
                "http://192.0.2.10/api/system/info",
                "http://192.0.2.10/api/system",
                "http://192.0.2.10/api/system/info",
                "http://192.0.2.10/api/system",
                "http://192.0.2.10/api/system/pools/0",
                "http://192.0.2.10/api/system/restart",
                "http://192.0.2.10/api/system/info",
            ]
        )

        let patchRequests = MultiPoolURLProtocolStub.capturedRequests.filter {
            $0.httpMethod == "PATCH"
        }
        // Only the new slot is written; untouched slots 2 and 3 stay out of the body.
        let poolsBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(patchRequests[0].capturedBody))
                as? [String: Any]
        )
        let sentPools = try XCTUnwrap(poolsBody["pools"] as? [[String: Any]])
        XCTAssertEqual(sentPools.compactMap { $0["id"] as? Int }, [1])
        XCTAssertEqual(sentPools[0]["stratumURL"] as? String, "solo.ckpool.org")
        XCTAssertEqual(sentPools[0]["stratumPort"] as? Int, 3333)
        XCTAssertEqual(sentPools[0]["stratumUser"] as? String, "bc1qnew.primary")
        XCTAssertEqual(sentPools[0]["stratumProtocol"] as? String, "SV1")
        XCTAssertNil(poolsBody["primaryPoolIndex"])
        XCTAssertNil(poolsBody["secondaryPoolIndex"])
        XCTAssertNil(poolsBody["useFallbackStratum"])
        // The selection follows once the slot was read back; unchanged keys are left out.
        let selectionBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(patchRequests[1].capturedBody))
                as? [String: Any]
        )
        XCTAssertEqual(selectionBody as? [String: Int], ["primaryPoolIndex": 1])

        let catalog = try XCTUnwrap(viewModel.poolCatalog)
        XCTAssertEqual(catalog.slots.map(\.id), [1, 2, 3])
        XCTAssertEqual(catalog.primaryPoolID, 1)
        XCTAssertEqual(catalog.secondaryPoolID, 3)
    }

    func testPoolCatalogSaveOfASpareSlotDoesNotMoveTheSelectionOrRestart() async throws {
        let appGroupDefaults = try XCTUnwrap(
            UserDefaults(suiteName: SettingsViewModel.sharedUserDefaultsSuiteName)
        )
        appGroupDefaults.set("192.0.2.10", forKey: "bitaxeIPAddress")
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent("esp-miner-2-15-0-system-info.json")
        let currentPayload = try Data(contentsOf: fixtureURL)
        let editedJSON = String(decoding: currentPayload, as: UTF8.self).replacing(
            "\"stratumURL\": \"unused.pool.example\"",
            with: "\"stratumURL\": \"spare.pool.example\""
        )
        XCTAssertNotEqual(editedJSON, String(decoding: currentPayload, as: UTF8.self))
        let editedPayload = Data(editedJSON.utf8)

        MultiPoolURLProtocolStub.requestHandler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            guard request.httpMethod == "GET" else {
                return (response, Data())
            }
            let didPatch = MultiPoolURLProtocolStub.capturedRequests.contains {
                $0.httpMethod == "PATCH"
            }
            return (response, didPatch ? editedPayload : currentPayload)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultiPoolURLProtocolStub.self]
        let schema = Schema([HistoricalDataPoint.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let viewModel = SettingsViewModel(
            sharedUserDefaults: appGroupDefaults,
            networkService: NetworkService(session: URLSession(configuration: configuration)),
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false
        )

        await viewModel.fetchDeviceSettings()
        var draft = try XCTUnwrap(viewModel.poolCatalog)
        MultiPoolURLProtocolStub.capturedRequests = []

        // Saving an untouched draft writes nothing.
        let didSaveUnchangedDraft = await viewModel.savePoolCatalog(draft)
        XCTAssertTrue(didSaveUnchangedDraft)
        XCTAssertEqual(
            MultiPoolURLProtocolStub.capturedRequests.map { $0.httpMethod },
            ["GET"]
        )
        MultiPoolURLProtocolStub.capturedRequests = []

        // Slot 0 is neither primary nor fallback, so editing it needs no restart.
        let spareIndex = try XCTUnwrap(draft.slots.firstIndex { $0.id == 0 })
        draft.slots[spareIndex].stratumURL = "spare.pool.example"

        let didSave = await viewModel.savePoolCatalog(draft)

        XCTAssertTrue(didSave)
        XCTAssertNil(viewModel.poolConfigurationError)
        XCTAssertEqual(
            MultiPoolURLProtocolStub.capturedRequests.map { $0.httpMethod },
            ["GET", "PATCH", "GET"]
        )
        let patchRequest = try XCTUnwrap(
            MultiPoolURLProtocolStub.capturedRequests.first { $0.httpMethod == "PATCH" }
        )
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(patchRequest.capturedBody))
                as? [String: Any]
        )
        let sentPools = try XCTUnwrap(body["pools"] as? [[String: Any]])
        XCTAssertEqual(sentPools.compactMap { $0["id"] as? Int }, [0])
        XCTAssertEqual(sentPools[0]["stratumURL"] as? String, "spare.pool.example")
        // The masked password and the properties Traxe does not edit are echoed back.
        XCTAssertEqual(sentPools[0]["stratumPassword"] as? String, "*****")
        XCTAssertEqual(sentPools[0]["stratumSuggestedDifficulty"] as? Int, 0)
        XCTAssertEqual(viewModel.poolCatalog?.slot(withID: 0)?.stratumURL, "spare.pool.example")
    }

    func testPoolCatalogSaveReportsFailureWhenTheMinerIgnoresTheSlotChanges() async throws {
        let appGroupDefaults = try XCTUnwrap(
            UserDefaults(suiteName: SettingsViewModel.sharedUserDefaultsSuiteName)
        )
        appGroupDefaults.set("192.0.2.10", forKey: "bitaxeIPAddress")
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent("esp-miner-2-15-0-system-info.json")
        let unchangedPayload = try Data(contentsOf: fixtureURL)

        MultiPoolURLProtocolStub.requestHandler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, request.httpMethod == "GET" ? unchangedPayload : Data())
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MultiPoolURLProtocolStub.self]
        let schema = Schema([HistoricalDataPoint.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let viewModel = SettingsViewModel(
            sharedUserDefaults: appGroupDefaults,
            networkService: NetworkService(session: URLSession(configuration: configuration)),
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false
        )

        await viewModel.fetchDeviceSettings()
        var draft = try XCTUnwrap(viewModel.poolCatalog)
        MultiPoolURLProtocolStub.capturedRequests = []

        let primaryIndex = try XCTUnwrap(draft.slots.firstIndex { $0.id == 2 })
        draft.slots[primaryIndex].stratumURL = "solo.ckpool.org"
        draft.primaryPoolID = 0

        let didSave = await viewModel.savePoolCatalog(draft)

        XCTAssertFalse(didSave)
        XCTAssertFalse(viewModel.isUpdatingPoolConfiguration)
        XCTAssertEqual(
            viewModel.poolConfigurationError,
            "The miner accepted the request but did not apply the pool settings. Please try again, or change the pool from the miner web UI."
        )
        // The selection is never moved, and the miner never restarted, when the slot write
        // did not stick.
        XCTAssertEqual(
            MultiPoolURLProtocolStub.capturedRequests.map { $0.httpMethod },
            ["GET", "PATCH", "GET"]
        )
        XCTAssertEqual(viewModel.poolCatalog?.primaryPoolID, 2)
    }

    // A v2.15 `/api/system/info` response after the pool changes were applied.
    private static let savedMultiPoolPayload = """
        {
          "hostname": "bitaxe-215",
          "version": "v2.15.0",
          "ASICModel": "BM1370",
          "hashRate": 1180.4,
          "autofanspeed": 1,
          "fanspeed": 60,
          "primaryPoolIndex": 2,
          "secondaryPoolIndex": 3,
          "useFallbackStratum": 1,
          "pools": [
            {
              "id": 0,
              "stratumProtocol": "SV1",
              "stratumURL": "unused.pool.example",
              "stratumPort": 3333,
              "stratumUser": "bc1qexample.unused",
              "stratumPassword": "*****",
              "stratumV2ChannelType": "extended",
              "stratumV2AuthorityPubkey": ""
            },
            {
              "id": 2,
              "stratumProtocol": "SV1",
              "stratumURL": "solo.ckpool.org",
              "stratumPort": 3333,
              "stratumUser": "bc1qnew.primary",
              "stratumPassword": "*****",
              "stratumV2ChannelType": "extended",
              "stratumV2AuthorityPubkey": ""
            },
            {
              "id": 3,
              "stratumProtocol": "SV2",
              "stratumURL": "eu.backup.example",
              "stratumPort": 4444,
              "stratumUser": "bc1qnew.backup",
              "stratumPassword": "*****",
              "stratumV2ChannelType": "standard",
              "stratumV2AuthorityPubkey": "9c4zpyJ2ndm4e8sP2uNc1VNCGxYjqaxWS6wUCjk8zFj6njFquH6"
            }
          ],
          "stratumURL": "solo.ckpool.org",
          "stratumPort": 3333,
          "stratumUser": "bc1qnew.primary",
          "stratumProtocol": "SV1",
          "stratumV2ChannelType": "extended",
          "stratumV2AuthorityPubkey": "",
          "fallbackStratumURL": "eu.backup.example",
          "fallbackStratumPort": 4444,
          "fallbackStratumUser": "bc1qnew.backup",
          "fallbackStratumProtocol": "SV2",
          "fallbackStratumV2ChannelType": "standard",
          "fallbackStratumV2AuthorityPubkey": "9c4zpyJ2ndm4e8sP2uNc1VNCGxYjqaxWS6wUCjk8zFj6njFquH6"
        }
        """
}

private final class MultiPoolURLProtocolStub: URLProtocol {
    struct CapturedRequest {
        let httpMethod: String?
        let url: URL?
        let capturedBody: Data?
    }

    nonisolated(unsafe) static var requestHandler:
        ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var capturedRequests: [CapturedRequest] = []

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
            Self.capturedRequests.append(
                CapturedRequest(
                    httpMethod: request.httpMethod,
                    url: request.url,
                    capturedBody: Self.bodyData(from: request)
                )
            )
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func bodyData(from request: URLRequest) -> Data? {
        if let httpBody = request.httpBody {
            return httpBody
        }

        guard let bodyStream = request.httpBodyStream else { return nil }
        bodyStream.open()
        defer { bodyStream.close() }

        var data = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while bodyStream.hasBytesAvailable {
            let readCount = bodyStream.read(buffer, maxLength: bufferSize)
            guard readCount > 0 else { break }
            data.append(buffer, count: readCount)
        }

        return data
    }
}
