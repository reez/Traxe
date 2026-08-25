import Foundation

struct SavedDevice: Identifiable, Codable, Hashable {
    struct RelocationRecord: Codable {
        let operationID: String
        let sequence: Int
        let previousIPAddress: String
        let currentIPAddress: String
        let cutoff: Date
    }

    /// Stable fallback identity for widgets, including miners without a known MAC.
    let id: UUID
    var name: String
    var ipAddress: String
    /// The miner's Wi-Fi MAC address as its firmware reports it, in the canonical form
    /// `normalizedMACAddress(_:)` produces. It is the miner's stable identity: the IP
    /// address is only where the miner was last reached. `nil` until the miner has
    /// answered once, which is also what payloads saved before this field decode to.
    var macAddress: String?
    /// Persisted with the address change so an interrupted move can be replayed.
    var relocationRecords: [RelocationRecord]
    /// Legacy saved records gain an ID on first load, then are written back once.
    let needsIdentifierMigration: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case ipAddress
        case macAddress
        case relocationRecords
    }

    init(name: String, ipAddress: String, macAddress: String? = nil) {
        self.id = UUID()
        self.name = name
        self.ipAddress = ipAddress
        self.macAddress = SavedDevice.normalizedMACAddress(macAddress)
        self.relocationRecords = []
        self.needsIdentifierMigration = false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let persistedID = try container.decodeIfPresent(UUID.self, forKey: .id)
        id = persistedID ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        ipAddress = try container.decode(String.self, forKey: .ipAddress)
        macAddress = SavedDevice.normalizedMACAddress(
            try container.decodeIfPresent(String.self, forKey: .macAddress)
        )
        relocationRecords =
            try container.decodeIfPresent([RelocationRecord].self, forKey: .relocationRecords) ?? []
        needsIdentifierMigration = persistedID == nil
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ipAddress)
    }

    static func == (lhs: SavedDevice, rhs: SavedDevice) -> Bool {
        lhs.ipAddress == rhs.ipAddress
    }

    /// The canonical `AA:BB:CC:DD:EE:FF` form of a MAC address, or `nil` when the value
    /// does not contain exactly 48 bits of hex. Firmware forks differ in case and
    /// separators, so comparisons only ever use this form.
    static func normalizedMACAddress(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let hexDigits = raw.uppercased().filter(\.isHexDigit)
        guard hexDigits.count == 12 else { return nil }

        var groups: [String] = []
        var index = hexDigits.startIndex
        while index < hexDigits.endIndex {
            let next = hexDigits.index(index, offsetBy: 2)
            groups.append(String(hexDigits[index..<next]))
            index = next
        }
        return groups.joined(separator: ":")
    }
}
