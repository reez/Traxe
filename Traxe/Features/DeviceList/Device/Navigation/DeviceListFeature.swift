/// A top-level feature the device list shows in its detail column.
///
/// Miners are identified by IP address rather than by a `SavedDevice` value so a
/// renamed, reordered, or re-fetched miner keeps the same navigation identity and a
/// stale copy of the model can never become the navigation state.
enum DeviceListFeature: Hashable {
    case miner(ipAddress: String)
    case fleetRecap
}
