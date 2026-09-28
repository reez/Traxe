import Foundation

/// Per-miner opt-in for the offline and hot notifications the widget refresh emits.
///
/// Preferences live in the app-group defaults so the widget extension reads exactly what
/// the Settings screen writes. Miners are keyed by IP address, matching `SavedDevice` and
/// the `savedDeviceIPs` list the widget already reads.
struct MinerAlertPreferences {
    static let appGroupID = "group.matthewramsden.traxe"

    private static let enabledIPAddressesKey = "minerAlertEnabledIPAddressesV1"
    private static let didMigrateLegacyGlobalKey = "minerAlertPerMinerMigrationV1"
    private static let legacyGlobalEnabledKey = "miner_alerts_enabled"
    private static let savedDeviceIPsKey = "savedDeviceIPs"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// `nil` when the app group is unavailable; alerts then stay off instead of being
    /// written somewhere the widget cannot read.
    static func appGroup() -> MinerAlertPreferences? {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return nil }
        return MinerAlertPreferences(defaults: defaults)
    }

    var enabledIPAddresses: Set<String> {
        Set(defaults.stringArray(forKey: Self.enabledIPAddressesKey) ?? [])
    }

    func isEnabled(for ipAddress: String) -> Bool {
        enabledIPAddresses.contains(ipAddress)
    }

    func setEnabled(_ isEnabled: Bool, for ipAddress: String) {
        guard !ipAddress.isEmpty else { return }
        var ipAddresses = enabledIPAddresses
        if isEnabled {
            ipAddresses.insert(ipAddress)
        } else {
            ipAddresses.remove(ipAddress)
        }
        store(ipAddresses)
    }

    /// Carries opt-ins along when DHCP moves miners, so alerts neither stop nor start
    /// just because an address changed. Moves are applied together so miners that
    /// swapped addresses each keep their own setting.
    func relocateOptIns(_ currentIPAddressByPrevious: [String: String]) {
        let ipAddresses = enabledIPAddresses
        let relocated = Set(ipAddresses.map { currentIPAddressByPrevious[$0] ?? $0 })
        guard relocated != ipAddresses else { return }
        store(relocated)
    }

    /// Removes a deleted miner's opt-in so an IP that is added again starts alerts off.
    func removePreference(for ipAddress: String) {
        var ipAddresses = enabledIPAddresses
        guard ipAddresses.remove(ipAddress) != nil else { return }
        store(ipAddresses)
    }

    /// Moves the legacy global `miner_alerts_enabled` switch onto the miners that were
    /// saved when this build first ran. It runs once, so miners added later default to
    /// alerts off.
    func migrateLegacyGlobalPreferenceIfNeeded() {
        guard !defaults.bool(forKey: Self.didMigrateLegacyGlobalKey) else { return }
        defaults.set(true, forKey: Self.didMigrateLegacyGlobalKey)

        guard defaults.bool(forKey: Self.legacyGlobalEnabledKey) else { return }
        let savedIPAddresses = defaults.stringArray(forKey: Self.savedDeviceIPsKey) ?? []
        store(enabledIPAddresses.union(savedIPAddresses))
    }

    private func store(_ ipAddresses: Set<String>) {
        defaults.set(ipAddresses.sorted(), forKey: Self.enabledIPAddressesKey)
    }
}
