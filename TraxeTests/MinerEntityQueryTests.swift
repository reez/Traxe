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
