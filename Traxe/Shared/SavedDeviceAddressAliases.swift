import Foundation

/// Maps the IP addresses a saved miner used to have to the address it answers at now.
///
/// Widget configurations and Shortcuts parameters created before miners had a MAC
/// address store the IP address as the miner's identifier, and a stored identifier
/// cannot be rewritten when DHCP moves the miner. These aliases let such identifiers
/// keep resolving to the same miner. They live in the app-group defaults so the widget
/// extension reads exactly what the app writes.
///
/// An alias means "the miner that used to be at this address", so recording a move
/// never removes an alias for the destination: a different miner may have lived there.
struct SavedDeviceAddressAliases {
    static let appGroupID = "group.matthewramsden.traxe"

    private static let aliasesKey = "savedDeviceAddressAliasesV1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// `nil` when the app group is unavailable, in which case identifiers resolve to
    /// themselves.
    static func appGroup() -> SavedDeviceAddressAliases? {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return nil }
        return SavedDeviceAddressAliases(defaults: defaults)
    }

    /// The address the miner once saved under `address` answers at now. Addresses that
    /// never moved resolve to themselves.
    func currentAddress(for address: String) -> String {
        aliases()[address] ?? address
    }

    /// Resolves a stored widget identifier against the current miners. A persisted
    /// device ID or learned MAC is stable, while a legacy IP identifier may belong
    /// to a miner that moved even when another miner now answers at that IP.
    static func indexOfMiner(
        identifiedBy identifier: String,
        in miners: [(id: String, macAddress: String?, ipAddress: String)],
        aliases: SavedDeviceAddressAliases?
    ) -> Int? {
        if let index = miners.firstIndex(where: {
            ($0.id == identifier && $0.id != $0.ipAddress)
                || $0.macAddress == identifier
        }) {
            return index
        }

        let currentAddress = aliases?.currentAddress(for: identifier) ?? identifier
        return miners.firstIndex(where: { $0.ipAddress == currentAddress })
    }

    /// Records that the miners at the keys of `currentByPrevious` now answer at the
    /// values. Moves are applied together so miners that swapped addresses each keep
    /// their own history, and older aliases are collapsed so every stale identifier
    /// points straight at a live address.
    func recordMoves(_ currentByPrevious: [String: String]) {
        let moves = currentByPrevious.filter { $0.key != $0.value }
        guard !moves.isEmpty else { return }

        var updated = aliases()
        for (stale, target) in updated {
            if let moved = moves[target] {
                updated[stale] = moved
            }
        }
        for (previous, current) in moves where updated[previous] == nil {
            // A different miner may have owned this address before the current mover.
            // Keep that older identifier with its original miner after IP reuse.
            updated[previous] = current
        }
        store(updated)
    }

    /// Forgets every alias that resolves to `address`, so a deleted miner's old
    /// identifiers cannot attach themselves to whatever answers at that address next.
    func removeAliases(resolvingTo address: String) {
        let remaining = aliases().filter { $0.value != address }
        store(remaining)
    }

    private func aliases() -> [String: String] {
        defaults.dictionary(forKey: Self.aliasesKey) as? [String: String] ?? [:]
    }

    private func store(_ aliases: [String: String]) {
        if aliases.isEmpty {
            defaults.removeObject(forKey: Self.aliasesKey)
        } else {
            defaults.set(aliases, forKey: Self.aliasesKey)
        }
    }
}
