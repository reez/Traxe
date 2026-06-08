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
}
