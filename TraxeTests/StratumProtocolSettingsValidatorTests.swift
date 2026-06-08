import XCTest

@testable import Traxe

final class StratumProtocolSettingsValidatorTests: XCTestCase {
    func testNormalizesSupportedProtocolAndChannelValues() {
        XCTAssertEqual(StratumProtocolSettingsValidator.protocolValueToSave(" sv2 "), "SV2")
        XCTAssertEqual(StratumProtocolSettingsValidator.protocolValueToSave(""), "SV1")
        XCTAssertEqual(StratumProtocolSettingsValidator.channelTypeToSave(" EXTENDED "), "extended")
        XCTAssertEqual(StratumProtocolSettingsValidator.channelTypeToSave(""), "standard")
    }

    func testRejectsUnsupportedProtocolAndChannelValues() {
        XCTAssertNil(StratumProtocolSettingsValidator.protocolValueToSave("SV3"))
        XCTAssertNil(StratumProtocolSettingsValidator.channelTypeToSave("solo"))
    }

    func testAcceptsEmptyAndValidAuthorityPubkeys() {
        XCTAssertNil(
            StratumProtocolSettingsValidator.authorityPubkeyValidationError(
                "",
                poolName: "Primary SV2"
            )
        )
        XCTAssertNil(
            StratumProtocolSettingsValidator.authorityPubkeyValidationError(
                "9c4zpyJ2ndm4e8sP2uNc1VNCGxYjqaxWS6wUCjk8zFj6njFquH6",
                poolName: "Primary SV2"
            )
        )
    }

    func testRejectsInvalidAuthorityPubkeys() {
        XCTAssertEqual(
            StratumProtocolSettingsValidator.authorityPubkeyValidationError(
                "9c4zpyJ2ndm4e8sP2uNc1VNCGxYjqaxWS6wUCjk8zFj6njFquH0",
                poolName: "Primary SV2"
            ),
            "Primary SV2 authority pubkey must use base58 characters."
        )
        XCTAssertEqual(
            StratumProtocolSettingsValidator.authorityPubkeyValidationError(
                "123456789ABCDEFGHJKLMNPQRSTUVWXYZ",
                poolName: "Primary SV2"
            ),
            "Primary SV2 authority pubkey must be 40 to 52 characters."
        )
    }
}
