import Foundation
import XCTest

@testable import Traxe

final class SavedDeviceAddressAliasesTests: XCTestCase {
    func testAddressThatNeverMovedResolvesToItself() throws {
        let suiteName = "SavedDeviceAddressAliasesTests.unmoved.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let aliases = SavedDeviceAddressAliases(defaults: defaults)

        XCTAssertEqual(aliases.currentAddress(for: "192.168.1.10"), "192.168.1.10")
    }

    func testRecordedMovesResolvePreviousAddressesAndCollapseOlderAliases() throws {
        let suiteName = "SavedDeviceAddressAliasesTests.collapse.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let aliases = SavedDeviceAddressAliases(defaults: defaults)

        aliases.recordMoves(["192.168.1.10": "192.168.1.20"])
        aliases.recordMoves(["192.168.1.20": "192.168.1.30"])

        XCTAssertEqual(aliases.currentAddress(for: "192.168.1.10"), "192.168.1.30")
        XCTAssertEqual(aliases.currentAddress(for: "192.168.1.20"), "192.168.1.30")
        XCTAssertEqual(aliases.currentAddress(for: "192.168.1.30"), "192.168.1.30")
    }

    func testSwappedAddressesEachResolveToTheirOwnMiner() throws {
        let suiteName = "SavedDeviceAddressAliasesTests.swap.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let aliases = SavedDeviceAddressAliases(defaults: defaults)

        aliases.recordMoves(["192.168.1.10": "192.168.1.11", "192.168.1.11": "192.168.1.10"])

        XCTAssertEqual(aliases.currentAddress(for: "192.168.1.10"), "192.168.1.11")
        XCTAssertEqual(aliases.currentAddress(for: "192.168.1.11"), "192.168.1.10")
    }

    func testSwappedAddressesKeepTheirOriginalOwnersThroughLaterMoves() throws {
        let suiteName = "SavedDeviceAddressAliasesTests.swapThenMove.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let aliases = SavedDeviceAddressAliases(defaults: defaults)

        aliases.recordMoves(["192.168.1.10": "192.168.1.11", "192.168.1.11": "192.168.1.10"])
        aliases.recordMoves(["192.168.1.11": "192.168.1.12"])

        XCTAssertEqual(aliases.currentAddress(for: "192.168.1.10"), "192.168.1.12")
        XCTAssertEqual(aliases.currentAddress(for: "192.168.1.11"), "192.168.1.10")

        aliases.recordMoves(["192.168.1.10": "192.168.1.13"])

        XCTAssertEqual(aliases.currentAddress(for: "192.168.1.10"), "192.168.1.12")
        XCTAssertEqual(aliases.currentAddress(for: "192.168.1.11"), "192.168.1.13")
    }

    func testWidgetIdentifiersDistinguishLegacyAndNewMinersAtReusedAddress() throws {
        let suiteName = "SavedDeviceAddressAliasesTests.widgetReuse.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let aliases = SavedDeviceAddressAliases(defaults: defaults)
        aliases.recordMoves(["192.168.1.10": "192.168.1.42"])
        var miners: [(id: String, macAddress: String?, ipAddress: String)] = [
            (id: "device:A", macAddress: "AA:BB:CC:DD:EE:01", ipAddress: "192.168.1.42"),
            (id: "device:B", macAddress: nil, ipAddress: "192.168.1.10"),
        ]

        XCTAssertEqual(
            SavedDeviceAddressAliases.indexOfMiner(
                identifiedBy: "192.168.1.10",
                in: miners,
                aliases: aliases
            ),
            0
        )
        XCTAssertEqual(
            SavedDeviceAddressAliases.indexOfMiner(
                identifiedBy: "device:B",
                in: miners,
                aliases: aliases
            ),
            1
        )
        XCTAssertEqual(
            SavedDeviceAddressAliases.indexOfMiner(
                identifiedBy: "AA:BB:CC:DD:EE:01",
                in: miners,
                aliases: aliases
            ),
            0
        )

        aliases.recordMoves(["192.168.1.10": "192.168.1.50"])
        miners[1] = (
            id: "device:B",
            macAddress: "AA:BB:CC:DD:EE:02",
            ipAddress: "192.168.1.50"
        )

        XCTAssertEqual(
            SavedDeviceAddressAliases.indexOfMiner(
                identifiedBy: "192.168.1.10",
                in: miners,
                aliases: aliases
            ),
            0
        )
        XCTAssertEqual(
            SavedDeviceAddressAliases.indexOfMiner(
                identifiedBy: "device:B",
                in: miners,
                aliases: aliases
            ),
            1
        )
    }

    func testWidgetIdentifierWithoutAliasFallsBackToCurrentIP() throws {
        let suiteName = "SavedDeviceAddressAliasesTests.widgetCurrentIP.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let miners: [(id: String, macAddress: String?, ipAddress: String)] = [
            (id: "192.168.1.10", macAddress: nil, ipAddress: "192.168.1.10")
        ]

        XCTAssertEqual(
            SavedDeviceAddressAliases.indexOfMiner(
                identifiedBy: "192.168.1.10",
                in: miners,
                aliases: SavedDeviceAddressAliases(defaults: defaults)
            ),
            0
        )
    }

    func testRemovingAliasesForDeletedMinerKeepsAliasesForOtherMiners() throws {
        let suiteName = "SavedDeviceAddressAliasesTests.delete.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let aliases = SavedDeviceAddressAliases(defaults: defaults)
        aliases.recordMoves(["192.168.1.10": "192.168.1.20"])
        aliases.recordMoves(["192.168.1.40": "192.168.1.50"])

        aliases.removeAliases(resolvingTo: "192.168.1.20")

        XCTAssertEqual(aliases.currentAddress(for: "192.168.1.10"), "192.168.1.10")
        XCTAssertEqual(aliases.currentAddress(for: "192.168.1.40"), "192.168.1.50")
    }
}
