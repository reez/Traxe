import AppIntents
import Foundation

struct MinerEntity: AppEntity {
    typealias ID = String

    let id: String
    let name: String
    let ipAddress: String

    /// Identifies the miner by MAC address once known, so the identifier a Shortcut
    /// stores survives DHCP moving the miner. Miners that have not answered yet fall
    /// back to the IP address.
    init(savedDevice: SavedDevice) {
        self.init(id: savedDevice.macAddress ?? savedDevice.ipAddress, savedDevice: savedDevice)
    }

    /// Keeps an identifier a Shortcut stored earlier while pointing at the miner's
    /// current address.
    init(id: String, savedDevice: SavedDevice) {
        self.id = id
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
