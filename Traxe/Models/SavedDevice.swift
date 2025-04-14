import Foundation

struct SavedDevice: Identifiable, Codable, Hashable {
    let id = UUID()
    var name: String
    let ipAddress: String

    private enum CodingKeys: String, CodingKey {
        case name
        case ipAddress
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ipAddress)
    }

    static func == (lhs: SavedDevice, rhs: SavedDevice) -> Bool {
        lhs.ipAddress == rhs.ipAddress
    }
}
