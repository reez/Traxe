import Foundation

// One ESP-Miner v2.15 pool slot as Pool Settings edits it. Slots are identified by the
// firmware's NVS index (0 to 7); users see them one-based, the way AxeOS labels them.
struct PoolSlotDraft: Identifiable, Equatable {
    static let maximumSlotCount = 8
    static let defaultStratumProtocol = "SV1"
    static let defaultStratumV2ChannelType = "standard"

    let id: Int
    var stratumURL: String = ""
    var stratumPortString: String = ""
    var stratumUser: String = ""
    var stratumProtocol: String = PoolSlotDraft.defaultStratumProtocol
    var stratumV2ChannelType: String = PoolSlotDraft.defaultStratumV2ChannelType
    var stratumV2AuthorityPubkey: String = ""

    init(id: Int) {
        self.id = id
    }

    init(pool: MinerPoolDTO, id: Int) {
        self.id = id
        stratumURL = pool.stratumURL ?? ""
        stratumPortString = pool.stratumPort.map { String($0) } ?? ""
        stratumUser = pool.stratumUser ?? ""
        stratumProtocol =
            StratumProtocolSettingsValidator.protocolValueToSave(pool.stratumProtocol ?? "")
            ?? Self.defaultStratumProtocol
        stratumV2ChannelType =
            StratumProtocolSettingsValidator.channelTypeToSave(pool.stratumV2ChannelType ?? "")
            ?? Self.defaultStratumV2ChannelType
        stratumV2AuthorityPubkey = pool.stratumV2AuthorityPubkey ?? ""
    }

    var title: String { "Pool \(id + 1)" }

    var trimmedStratumURL: String {
        stratumURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedStratumPortString: String {
        stratumPortString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedStratumUser: String {
        stratumUser.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // A slot the user has not filled in yet. It stays out of every request.
    var isBlank: Bool {
        trimmedStratumURL.isEmpty && trimmedStratumPortString.isEmpty
            && trimmedStratumUser.isEmpty
    }

    var menuLabel: String {
        trimmedStratumURL.isEmpty ? "\(title) · New Pool" : "\(title) · \(trimmedStratumURL)"
    }

    // The complete pool object this slot should hold on the miner. `nil` for a blank slot or
    // one that does not pass `PoolCatalogSavePlan.validationError(for:)` yet.
    var settingsEdit: PoolSettingsEdit? {
        guard !isBlank, let port = Int(trimmedStratumPortString) else { return nil }
        return PoolSettingsEdit(
            id: id,
            stratumURL: trimmedStratumURL,
            stratumPort: port,
            stratumUser: trimmedStratumUser,
            stratumProtocol: StratumProtocolSettingsValidator.protocolValueToSave(stratumProtocol),
            stratumV2ChannelType: StratumProtocolSettingsValidator.channelTypeToSave(
                stratumV2ChannelType
            ),
            stratumV2AuthorityPubkey: StratumProtocolSettingsValidator.trimmedAuthorityPubkey(
                stratumV2AuthorityPubkey
            )
        )
    }
}

// Everything Pool Settings edits on an ESP-Miner v2.15 miner: the slot list, which slots are
// the primary and fallback, and whether the miner is held on the fallback.
struct PoolCatalogDraft: Equatable {
    var slots: [PoolSlotDraft]
    var primaryPoolID: Int
    var secondaryPoolID: Int
    var useFallbackStratum: Bool
    // Slots removed from the list. They are cleared on the miner when saving.
    var deletedPoolIDs: [Int] = []

    init(
        slots: [PoolSlotDraft],
        primaryPoolID: Int,
        secondaryPoolID: Int,
        useFallbackStratum: Bool
    ) {
        self.slots = slots.sorted { $0.id < $1.id }
        self.primaryPoolID = primaryPoolID
        self.secondaryPoolID = secondaryPoolID
        self.useFallbackStratum = useFallbackStratum
    }

    // The miner only serializes slots it has configured. Like AxeOS, the selected primary and
    // fallback slots are always listed, as blank slots when the miner has nothing in them.
    init(systemInfo: SystemInfoDTO) {
        var slots = (systemInfo.pools ?? []).compactMap { pool -> PoolSlotDraft? in
            guard let id = pool.id, (0..<PoolSlotDraft.maximumSlotCount).contains(id) else {
                return nil
            }
            return PoolSlotDraft(pool: pool, id: id)
        }
        for selectedID in [systemInfo.primaryPoolID, systemInfo.secondaryPoolID]
        where !slots.contains(where: { $0.id == selectedID }) {
            slots.append(PoolSlotDraft(id: selectedID))
        }
        self.init(
            slots: slots,
            primaryPoolID: systemInfo.primaryPoolID,
            secondaryPoolID: systemInfo.secondaryPoolID,
            useFallbackStratum: systemInfo.useFallbackStratum ?? false
        )
    }

    func slot(withID id: Int) -> PoolSlotDraft? {
        slots.first { $0.id == id }
    }

    func isSelected(_ id: Int) -> Bool {
        id == primaryPoolID || id == secondaryPoolID
    }

    var nextFreeSlotID: Int? {
        (0..<PoolSlotDraft.maximumSlotCount).first { id in !slots.contains { $0.id == id } }
    }

    var canAddSlot: Bool { nextFreeSlotID != nil }

    @discardableResult
    mutating func addSlot() -> PoolSlotDraft? {
        guard let id = nextFreeSlotID else { return nil }
        let slot = PoolSlotDraft(id: id)
        slots.append(slot)
        slots.sort { $0.id < $1.id }
        deletedPoolIDs.removeAll { $0 == id }
        return slot
    }

    // The firmware refuses to clear a slot that is selected as primary or fallback, so the
    // draft refuses too instead of failing at save time.
    @discardableResult
    mutating func deleteSlot(withID id: Int) -> Bool {
        guard !isSelected(id), let index = slots.firstIndex(where: { $0.id == id }) else {
            return false
        }
        slots.remove(at: index)
        if !deletedPoolIDs.contains(id) {
            deletedPoolIDs.append(id)
        }
        return true
    }
}

// Turns a `PoolCatalogDraft` into the ESP-Miner v2.15 requests that apply it, and checks
// afterwards that the miner really did: v2.15 answers a PATCH with HTTP success even when it
// ignored the submitted properties.
enum PoolCatalogSavePlan {
    struct SelectionChange: Equatable {
        var primaryPoolIndex: Int? = nil
        var secondaryPoolIndex: Int? = nil
        var useFallbackStratum: Bool? = nil

        var isEmpty: Bool {
            primaryPoolIndex == nil && secondaryPoolIndex == nil && useFallbackStratum == nil
        }
    }

    static func validationError(for draft: PoolCatalogDraft) -> String? {
        for slot in draft.slots where !slot.isBlank {
            let host = slot.trimmedStratumURL
            guard !host.isEmpty, !slot.trimmedStratumUser.isEmpty,
                let port = Int(slot.trimmedStratumPortString), (1...65535).contains(port)
            else {
                return "\(slot.title) needs a host, a port between 1 and 65535, and a user."
            }
            if host.contains("://") || host.range(of: #":\d+$"#, options: .regularExpression) != nil
            {
                return "\(slot.title) host must not include 'stratum+tcp://' or a port."
            }
            if let protocolError = StratumProtocolSettingsValidator.validationError(
                protocolValue: slot.stratumProtocol,
                channelType: slot.stratumV2ChannelType,
                authorityPubkey: slot.stratumV2AuthorityPubkey,
                poolName: "\(slot.title) SV2"
            ) {
                return protocolError
            }
        }

        guard draft.primaryPoolID != draft.secondaryPoolID else {
            return "The primary and fallback must be different pools."
        }
        guard let primary = draft.slot(withID: draft.primaryPoolID), !primary.isBlank else {
            return "Fill in the primary pool's host, port and user before saving."
        }
        guard let secondary = draft.slot(withID: draft.secondaryPoolID) else {
            return "Pick a fallback pool before saving."
        }
        if draft.useFallbackStratum, secondary.isBlank {
            return "Fill in \(secondary.title) before selecting the fallback as the active pool."
        }
        return nil
    }

    static func settingsEdits(for draft: PoolCatalogDraft) -> [PoolSettingsEdit] {
        draft.slots.compactMap { $0.settingsEdit }
    }

    // Pool objects to PATCH: only the slots whose values differ from what the miner reports.
    static func poolsToSave(
        for draft: PoolCatalogDraft,
        from systemInfo: SystemInfoDTO
    ) -> [MinerPoolDTO] {
        let edits = settingsEdits(for: draft)
        let changedIDs = Set(MultiPoolSettingsPlan.unsavedPoolIDs(for: edits, in: systemInfo))
        return MultiPoolSettingsPlan.pools(
            for: edits.filter { changedIDs.contains($0.id) },
            from: systemInfo
        )
    }

    static func selectionChange(
        for draft: PoolCatalogDraft,
        from systemInfo: SystemInfoDTO
    ) -> SelectionChange {
        SelectionChange(
            primaryPoolIndex: draft.primaryPoolID == systemInfo.primaryPoolID
                ? nil : draft.primaryPoolID,
            secondaryPoolIndex: draft.secondaryPoolID == systemInfo.secondaryPoolID
                ? nil : draft.secondaryPoolID,
            useFallbackStratum: systemInfo.supportsActivePoolSelection
                && systemInfo.useFallbackStratum != draft.useFallbackStratum
                ? draft.useFallbackStratum : nil
        )
    }

    // Slots to clear on the miner: removed in the draft and still present on the miner.
    static func poolIDsToDelete(
        for draft: PoolCatalogDraft,
        from systemInfo: SystemInfoDTO
    ) -> [Int] {
        draft.deletedPoolIDs
            .filter { id in systemInfo.pool(withID: id) != nil && draft.slot(withID: id) == nil }
            .sorted()
    }

    // The miner reads its pool selection while booting, so it has to restart when the slots it
    // mines on change. Editing a spare slot or clearing one takes effect without a restart.
    static func requiresRestart(
        for draft: PoolCatalogDraft,
        poolsToSave: [MinerPoolDTO],
        selectionChange: SelectionChange
    ) -> Bool {
        !selectionChange.isEmpty
            || poolsToSave.contains { pool in pool.id.map(draft.isSelected) ?? false }
    }

    // Whether a freshly fetched system info reports everything the draft asked for.
    static func isApplied(_ draft: PoolCatalogDraft, in systemInfo: SystemInfoDTO) -> Bool {
        MultiPoolSettingsPlan.unsavedPoolIDs(for: settingsEdits(for: draft), in: systemInfo).isEmpty
            && poolIDsToDelete(for: draft, from: systemInfo).isEmpty
            && systemInfo.primaryPoolID == draft.primaryPoolID
            && systemInfo.secondaryPoolID == draft.secondaryPoolID
            && (!systemInfo.supportsActivePoolSelection
                || systemInfo.useFallbackStratum == draft.useFallbackStratum)
    }
}
