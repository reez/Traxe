import XCTest

@testable import Traxe

final class MinerEntityQueryTests: XCTestCase {
    func testEntitiesForIdentifiersResolvesSavedDevicesOutsideAccessibleSubset() async throws {
        let devices = [
            SavedDevice(name: "Miner 1", ipAddress: "192.168.1.10"),
            SavedDevice(name: "Miner 2", ipAddress: "192.168.1.11"),
        ]
        let query = makeQuery(
            devices: devices,
            accessPolicy: .init(
                proIsActive: false,
                miners5IsActive: false,
                hasLoadedSubscription: true
            )
        )

        let entities = try await query.entities(for: ["192.168.1.11"])

        XCTAssertEqual(entities.map(\.id), ["192.168.1.11"])
        XCTAssertEqual(entities.first?.name, "Miner 2")
    }

    func testEntitiesForIdentifiersFollowMovedMinerThroughMACAndAddressAlias() async throws {
        let devices = [
            SavedDevice(name: "Miner 1", ipAddress: "192.168.1.42", macAddress: "AA:BB:CC:DD:EE:01")
        ]
        let query = MinerEntityQuery(
            loadSavedDevices: { devices },
            resolveSubscriptionAccessPolicy: {
                .init(proIsActive: true, miners5IsActive: false, hasLoadedSubscription: true)
            },
            resolveCurrentIPAddress: { identifier in
                identifier == "192.168.1.10" ? "192.168.1.42" : identifier
            }
        )

        let byMACAddress = try await query.entities(for: ["AA:BB:CC:DD:EE:01"])
        XCTAssertEqual(byMACAddress.map(\.id), ["AA:BB:CC:DD:EE:01"])
        XCTAssertEqual(byMACAddress.first?.ipAddress, "192.168.1.42")

        let byPreviousAddress = try await query.entities(for: ["192.168.1.10"])
        XCTAssertEqual(byPreviousAddress.map(\.id), ["192.168.1.10"])
        XCTAssertEqual(byPreviousAddress.first?.ipAddress, "192.168.1.42")

        let suggested = try await query.suggestedEntities()
        XCTAssertEqual(suggested.map(\.id), ["AA:BB:CC:DD:EE:01"])
    }

    func testSuggestedEntitiesRemainLimitedToAccessibleDevices() async throws {
        let devices = [
            SavedDevice(name: "Miner 1", ipAddress: "192.168.1.10"),
            SavedDevice(name: "Miner 2", ipAddress: "192.168.1.11"),
        ]
        let query = makeQuery(
            devices: devices,
            accessPolicy: .init(
                proIsActive: false,
                miners5IsActive: false,
                hasLoadedSubscription: true
            )
        )

        let entities = try await query.suggestedEntities()

        XCTAssertEqual(entities.map(\.id), ["192.168.1.10"])
    }

    private func makeQuery(
        devices: [SavedDevice],
        accessPolicy: SubscriptionAccessPolicy
    ) -> MinerEntityQuery {
        MinerEntityQuery(
            loadSavedDevices: { devices },
            resolveSubscriptionAccessPolicy: { accessPolicy }
        )
    }
}
