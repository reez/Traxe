import Foundation

// The pool values Traxe's settings UI can edit for one ESP-Miner v2.15 pool slot.
struct PoolSettingsEdit: Equatable {
    let id: Int
    var stratumURL: String? = nil
    var stratumPort: Int? = nil
    var stratumUser: String? = nil
    var stratumProtocol: String? = nil
    var stratumV2ChannelType: String? = nil
    var stratumV2AuthorityPubkey: String? = nil

    // Only the properties the user actually supplied. Everything else has to come from the
    // miner's own pool object because ESP-Miner applies a firmware default to any pool
    // property missing from the PATCH body.
    var editedProperties: [String: FirmwareJSONValue] {
        var properties: [String: FirmwareJSONValue] = [:]
        if let stratumURL, !stratumURL.isEmpty {
            properties[MinerPoolDTO.stratumURLKey] = .string(stratumURL)
        }
        if let stratumPort {
            properties[MinerPoolDTO.stratumPortKey] = .int(stratumPort)
        }
        if let stratumUser, !stratumUser.isEmpty {
            properties[MinerPoolDTO.stratumUserKey] = .string(stratumUser)
        }
        if let stratumProtocol {
            properties[MinerPoolDTO.stratumProtocolKey] = .string(stratumProtocol)
        }
        if let stratumV2ChannelType {
            properties[MinerPoolDTO.stratumV2ChannelTypeKey] = .string(stratumV2ChannelType)
        }
        if let stratumV2AuthorityPubkey {
            properties[MinerPoolDTO.stratumV2AuthorityPubkeyKey] = .string(
                stratumV2AuthorityPubkey
            )
        }
        return properties
    }

    // Traxe omits blank fields, so a slot without a URL and without a user is not being
    // configured at all. The protocol defaults on their own must not rewrite or create a pool.
    fileprivate var isConfigured: Bool {
        stratumURL?.isEmpty == false || stratumUser?.isEmpty == false
    }

    fileprivate var hasRequiredPropertiesForNewPool: Bool {
        stratumURL?.isEmpty == false && stratumPort != nil && stratumUser?.isEmpty == false
    }
}

// Maps Traxe's pool settings onto the ESP-Miner v2.15 `pools` array and checks afterwards
// whether the miner really applied them: v2.15 answers a PATCH with HTTP success even when
// it ignored the submitted properties.
enum MultiPoolSettingsPlan {
    // Builds the pool objects to PATCH, preserving every property the miner reported for
    // those slots, including the masked `stratumPassword` that tells v2.15 to keep the
    // stored password.
    static func pools(
        for edits: [PoolSettingsEdit],
        from systemInfo: SystemInfoDTO
    ) -> [MinerPoolDTO] {
        edits.compactMap { edit in
            let editedProperties = edit.editedProperties
            guard edit.isConfigured, !editedProperties.isEmpty else { return nil }

            guard var properties = systemInfo.pool(withID: edit.id)?.properties else {
                // The miner only serializes pool slots it has configured, so a slot the user
                // is filling in for the first time has nothing to preserve. ESP-Miner rejects
                // a pool object without a URL, port and user, so only create one once the
                // user supplied all three.
                guard edit.hasRequiredPropertiesForNewPool else { return nil }
                var newProperties = editedProperties
                newProperties[MinerPoolDTO.idKey] = .int(edit.id)
                return MinerPoolDTO(properties: newProperties)
            }

            properties[MinerPoolDTO.idKey] = .int(edit.id)
            properties.merge(editedProperties) { _, edited in edited }
            return MinerPoolDTO(properties: properties)
        }
    }

    // Pool slots whose submitted values are missing from a freshly fetched system info.
    static func unsavedPoolIDs(
        for edits: [PoolSettingsEdit],
        in systemInfo: SystemInfoDTO
    ) -> [Int] {
        edits.compactMap { edit in
            let editedProperties = edit.editedProperties
            guard edit.isConfigured, !editedProperties.isEmpty else { return nil }
            guard let pool = systemInfo.pool(withID: edit.id) else { return edit.id }

            let didApplyEdits = editedProperties.allSatisfy { key, editedValue in
                pool.properties[key]?.isEquivalent(to: editedValue) ?? false
            }
            return didApplyEdits ? nil : edit.id
        }
    }
}
