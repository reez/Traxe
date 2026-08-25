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
        // Pool indices and fallback usage are not edited by this screen.
        XCTAssertNil(body["primaryPoolIndex"])
        XCTAssertNil(body["secondaryPoolIndex"])
        XCTAssertNil(body["useFallbackStratum"])
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
