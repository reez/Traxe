import Foundation

enum StratumProtocolSettingsValidator {
    private static let base58Alphabet = Set(
        "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    )

    static func protocolValueToSave(_ value: String) -> String? {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalizedValue.isEmpty { return "SV1" }
        return ["SV1", "SV2"].contains(normalizedValue) ? normalizedValue : nil
    }

    static func channelTypeToSave(_ value: String) -> String? {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedValue.isEmpty { return "standard" }
        return ["standard", "extended"].contains(normalizedValue) ? normalizedValue : nil
    }

    static func trimmedAuthorityPubkey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func validationError(
        protocolValue: String,
        channelType: String,
        authorityPubkey: String,
        poolName: String
    ) -> String? {
        guard protocolValueToSave(protocolValue) != nil else {
            return "\(poolName) protocol must be Stratum V1 or Stratum V2."
        }

        guard channelTypeToSave(channelType) != nil else {
            return "\(poolName) SV2 channel must be Standard Channels or Extended Channels."
        }

        return authorityPubkeyValidationError(authorityPubkey, poolName: poolName)
    }

    static func authorityPubkeyValidationError(_ value: String, poolName: String) -> String? {
        let trimmedValue = trimmedAuthorityPubkey(value)
        guard !trimmedValue.isEmpty else { return nil }

        guard trimmedValue.allSatisfy({ base58Alphabet.contains($0) }) else {
            return "\(poolName) authority pubkey must use base58 characters."
        }

        guard (40...52).contains(trimmedValue.count) else {
            return "\(poolName) authority pubkey must be 40 to 52 characters."
        }

        return nil
    }
}
