import Foundation

/// A saved miner that was found answering at a different IP address than the one it
/// was saved under, identified by its MAC address.
struct DeviceRelocation: Equatable, Sendable {
    let macAddress: String
    let previousIPAddress: String
    let currentIPAddress: String
}
