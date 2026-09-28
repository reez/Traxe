import Foundation
import XCTest

@testable import Traxe

final class SavedDeviceTests: XCTestCase {
    func testDecodingPayloadSavedBeforeMACAddressesLeavesMACAddressNil() throws {
        let legacyJSON = Data(#"[{"name":"Miner A","ipAddress":"192.168.1.10"}]"#.utf8)

        let devices = try JSONDecoder().decode([SavedDevice].self, from: legacyJSON)

        XCTAssertEqual(devices.map(\.ipAddress), ["192.168.1.10"])
        XCTAssertEqual(devices.first?.name, "Miner A")
        XCTAssertNil(devices.first?.macAddress)
    }

    func testEncodingOmitsMACAddressUntilKnownAndRoundTripsItOnceLearned() throws {
        let unknown = SavedDevice(name: "Miner A", ipAddress: "192.168.1.10")
        let unknownJSON = String(decoding: try JSONEncoder().encode(unknown), as: UTF8.self)
        XCTAssertFalse(unknownJSON.contains("macAddress"))

        let known = SavedDevice(
            name: "Miner A",
            ipAddress: "192.168.1.10",
            macAddress: "aa:bb:cc:dd:ee:ff"
        )
        let decoded = try JSONDecoder().decode(
            SavedDevice.self,
            from: try JSONEncoder().encode(known)
        )
        XCTAssertEqual(decoded.macAddress, "AA:BB:CC:DD:EE:FF")
    }

    func testLegacyDeviceGainsPersistentIdentifierWhenEncoded() throws {
        let legacyJSON = Data(#"[{"name":"Miner A","ipAddress":"192.168.1.10"}]"#.utf8)
        let legacyDevice = try XCTUnwrap(
            JSONDecoder().decode([SavedDevice].self, from: legacyJSON).first
        )
        XCTAssertTrue(legacyDevice.needsIdentifierMigration)

        let migratedJSON = try JSONEncoder().encode([legacyDevice])
        let restoredDevice = try XCTUnwrap(
            JSONDecoder().decode([SavedDevice].self, from: migratedJSON).first
        )

        XCTAssertEqual(restoredDevice.id, legacyDevice.id)
        XCTAssertFalse(restoredDevice.needsIdentifierMigration)
    }

    func testDecodingNormalizesStoredMACAddress() throws {
        let json = Data(
            #"[{"name":"Miner A","ipAddress":"192.168.1.10","macAddress":"aa-bb-cc-dd-ee-ff"}]"#
                .utf8
        )

        let devices = try JSONDecoder().decode([SavedDevice].self, from: json)

        XCTAssertEqual(devices.first?.macAddress, "AA:BB:CC:DD:EE:FF")
    }

    func testNormalizedMACAddressAcceptsFirmwareFormatsAndRejectsOtherValues() {
        XCTAssertEqual(SavedDevice.normalizedMACAddress("aa:bb:cc:dd:ee:ff"), "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(SavedDevice.normalizedMACAddress("AA-BB-CC-DD-EE-FF"), "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(SavedDevice.normalizedMACAddress("aabbccddeeff"), "AA:BB:CC:DD:EE:FF")
        XCTAssertNil(SavedDevice.normalizedMACAddress(nil))
        XCTAssertNil(SavedDevice.normalizedMACAddress(""))
        XCTAssertNil(SavedDevice.normalizedMACAddress("Unknown"))
        XCTAssertNil(SavedDevice.normalizedMACAddress("AA:BB:CC:DD:EE"))
    }
}
