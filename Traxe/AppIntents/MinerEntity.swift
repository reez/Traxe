import AppIntents
import Foundation

struct MinerEntity: AppEntity {
    typealias ID = String

    let id: String
    let name: String
    let ipAddress: String

    init(savedDevice: SavedDevice) {
        self.id = savedDevice.ipAddress
        self.name = savedDevice.name
        self.ipAddress = savedDevice.ipAddress
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Miner"
    }

    static var defaultQuery: MinerEntityQuery = .init()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(ipAddress)"
        )
    }
}
