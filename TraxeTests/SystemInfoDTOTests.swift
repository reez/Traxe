import XCTest

@testable import Traxe

final class SystemInfoDTOTests: XCTestCase {
    func testDecodesStratumV2Settings() throws {
        let payload = """
            {
                "hostname": "bitaxe",
                "version": "v2.14.0",
                "stratumURL": "public-pool.io",
                "stratumPort": 3333,
                "stratumUser": "bc1qexample.worker",
                "fallbackStratumURL": "backup.pool.example",
                "fallbackStratumPort": 4333,
                "fallbackStratumUser": "bc1qexample.backup",
                "stratumProtocol": "SV2",
                "fallbackStratumProtocol": "SV1",
                "stratumV2ChannelType": "extended",
                "fallbackStratumV2ChannelType": "standard",
                "stratumV2AuthorityPubkey": "9c4zpyJ2ndm4e8sP2uNc1VNCGxYjqaxWS6wUCjk8zFj6njFquH6",
                "fallbackStratumV2AuthorityPubkey": "backupAuthorityPubkey"
            }
            """

        let systemInfo = try JSONDecoder().decode(SystemInfoDTO.self, from: Data(payload.utf8))

        XCTAssertTrue(systemInfo.supportsStratumProtocolSettings)
        XCTAssertEqual(systemInfo.stratumProtocol, "SV2")
        XCTAssertEqual(systemInfo.fallbackStratumProtocol, "SV1")
        XCTAssertEqual(systemInfo.stratumV2ChannelType, "extended")
        XCTAssertEqual(systemInfo.fallbackStratumV2ChannelType, "standard")
        XCTAssertEqual(
            systemInfo.stratumV2AuthorityPubkey,
            "9c4zpyJ2ndm4e8sP2uNc1VNCGxYjqaxWS6wUCjk8zFj6njFquH6"
        )
        XCTAssertEqual(systemInfo.fallbackStratumV2AuthorityPubkey, "backupAuthorityPubkey")
    }

    func testOlderPayloadDoesNotReportStratumProtocolSettingsSupport() throws {
        let payload = """
            {
                "hostname": "bitaxe",
                "version": "v2.13.0",
                "stratumURL": "pool.example",
                "stratumPort": 3333,
                "stratumUser": "bc1qexample.worker"
            }
            """

        let systemInfo = try JSONDecoder().decode(SystemInfoDTO.self, from: Data(payload.utf8))

        XCTAssertFalse(systemInfo.supportsStratumProtocolSettings)
        XCTAssertNil(systemInfo.stratumProtocol)
        XCTAssertNil(systemInfo.fallbackStratumProtocol)
        XCTAssertNil(systemInfo.stratumV2ChannelType)
        XCTAssertNil(systemInfo.fallbackStratumV2ChannelType)
        XCTAssertNil(systemInfo.stratumV2AuthorityPubkey)
        XCTAssertNil(systemInfo.fallbackStratumV2AuthorityPubkey)
    }

    func testDecodesNerdQaxeNumericStratumSettings() throws {
        let payload = """
            {
                "hostname": "nerdqaxe-plus",
                "version": "V1.0.37.2-LTS",
                "deviceModel": "NerdQAxe++",
                "stratumURL": "pool.example",
                "stratumPort": 3333,
                "stratumUser": "bc1qexample.primary",
                "fallbackStratumURL": "fallback.pool.example",
                "fallbackStratumPort": 4333,
                "fallbackStratumUser": "bc1qexample.fallback",
                "stratumProtocol": 1,
                "fallbackStratumProtocol": 0,
                "sv2ChannelType": 0,
                "fallbackSv2ChannelType": 1,
                "sv2AuthorityPubkey": "primaryAuthorityPubkey",
                "fallbackSv2AuthorityPubkey": "fallbackAuthorityPubkey",
                "hashRate": 1234000,
                "bestDiff": 12345,
                "bestSessionDiff": 67890
            }
            """

        let systemInfo = try JSONDecoder().decode(SystemInfoDTO.self, from: Data(payload.utf8))

        XCTAssertTrue(systemInfo.supportsStratumProtocolSettings)
        XCTAssertEqual(systemInfo.deviceType, .nerdqaxe)
        XCTAssertEqual(systemInfo.stratumProtocol, "SV2")
        XCTAssertEqual(systemInfo.fallbackStratumProtocol, "SV1")
        XCTAssertEqual(systemInfo.stratumV2ChannelType, "extended")
        XCTAssertEqual(systemInfo.fallbackStratumV2ChannelType, "standard")
        XCTAssertEqual(systemInfo.stratumV2AuthorityPubkey, "primaryAuthorityPubkey")
        XCTAssertEqual(systemInfo.fallbackStratumV2AuthorityPubkey, "fallbackAuthorityPubkey")
        XCTAssertEqual(systemInfo.hashrate, 1234)
        XCTAssertEqual(systemInfo.bestDiff, "12345")
        XCTAssertEqual(systemInfo.bestSessionDiff, "67890")
    }

    func testDecodesEspMiner215MultiPoolSystemInfoAlongsideLegacyFlatFields() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent("esp-miner-2-15-0-system-info.json")
        let payload = try Data(contentsOf: fixtureURL)

        let systemInfo = try JSONDecoder().decode(SystemInfoDTO.self, from: payload)

        XCTAssertTrue(systemInfo.supportsMultiPoolSettings)
        XCTAssertFalse(systemInfo.supportsPoolModeSettings)
        XCTAssertEqual(systemInfo.pools?.count, 3)
        XCTAssertEqual(systemInfo.pools?.compactMap(\.id), [0, 2, 3])
        XCTAssertEqual(systemInfo.primaryPoolIndex, 2)
        XCTAssertEqual(systemInfo.secondaryPoolIndex, 3)
        XCTAssertEqual(systemInfo.primaryPoolID, 2)
        XCTAssertEqual(systemInfo.secondaryPoolID, 3)
        XCTAssertEqual(systemInfo.useFallbackStratum, true)
        XCTAssertTrue(systemInfo.supportsActivePoolSelection)

        let primaryPool = try XCTUnwrap(systemInfo.pool(withID: 2))
        XCTAssertEqual(primaryPool.stratumURL, "public-pool.io")
        XCTAssertEqual(primaryPool.stratumPort, 21496)
        XCTAssertEqual(primaryPool.stratumUser, "bc1qexample.primary")
        XCTAssertEqual(primaryPool.stratumPassword, "*****")
        XCTAssertEqual(primaryPool.properties["stratumTLS"], .int(1))
        XCTAssertEqual(primaryPool.properties["stratumExtranonceSubscribe"], .bool(true))
        XCTAssertEqual(
            primaryPool.properties["stratumFutureFlags"],
            .object(["nested": .array([.int(1), .bool(true), .null])])
        )

        let secondaryPool = try XCTUnwrap(systemInfo.pool(withID: 3))
        XCTAssertEqual(secondaryPool.stratumURL, "backup.pool.example")
        XCTAssertEqual(secondaryPool.stratumPort, 4333)
        XCTAssertEqual(secondaryPool.properties["stratumV2ChannelType"], .string("standard"))

        // The legacy flat properties are still reported by v2.15 and still decode.
        XCTAssertEqual(systemInfo.stratumURL, "public-pool.io")
        XCTAssertEqual(systemInfo.stratumPort, 21496)
        XCTAssertEqual(systemInfo.stratumUser, "bc1qexample.primary")
        XCTAssertEqual(systemInfo.fallbackStratumURL, "backup.pool.example")
        XCTAssertEqual(systemInfo.fallbackStratumPort, 4333)
        XCTAssertEqual(systemInfo.fallbackStratumUser, "bc1qexample.backup")
        XCTAssertTrue(systemInfo.supportsStratumProtocolSettings)
        XCTAssertEqual(systemInfo.stratumProtocol, "SV1")
        XCTAssertEqual(systemInfo.fallbackStratumProtocol, "SV2")
    }

    func testLegacyFirmwareWithoutPoolsDoesNotReportMultiPoolSupport() throws {
        let payload = """
            {
                "hostname": "bitaxe",
                "version": "v2.14.2",
                "stratumURL": "pool.example",
                "stratumPort": 3333,
                "stratumUser": "bc1qexample.worker"
            }
            """

        let systemInfo = try JSONDecoder().decode(SystemInfoDTO.self, from: Data(payload.utf8))

        XCTAssertFalse(systemInfo.supportsMultiPoolSettings)
        XCTAssertFalse(systemInfo.supportsPoolModeSettings)
        XCTAssertNil(systemInfo.pools)
        XCTAssertNil(systemInfo.primaryPoolIndex)
        XCTAssertNil(systemInfo.secondaryPoolIndex)
        XCTAssertNil(systemInfo.useFallbackStratum)
        XCTAssertFalse(systemInfo.supportsActivePoolSelection)
        XCTAssertEqual(systemInfo.primaryPoolID, 0)
        XCTAssertEqual(systemInfo.secondaryPoolID, 1)
    }
}
