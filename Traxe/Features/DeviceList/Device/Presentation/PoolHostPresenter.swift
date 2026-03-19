import Foundation

struct PoolHostMetadata: Equatable, Sendable {
    let normalizedHost: String
    let displayName: String
    let logoName: String?
    let poolSlug: String?
}

enum PoolHostPresenter {
    static func metadata(from raw: String) -> PoolHostMetadata? {
        guard let normalizedHost = normalizedHost(from: raw) else {
            return nil
        }

        return PoolHostMetadata(
            normalizedHost: normalizedHost,
            displayName: displayName(for: normalizedHost),
            logoName: logoName(for: normalizedHost),
            poolSlug: poolSlug(for: normalizedHost)
        )
    }

    static func normalizedHost(from raw: String) -> String? {
        let base = raw.split(separator: "(").first.map(String.init) ?? ""
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let host = url.host {
            return host.lowercased()
        }

        if let url = URL(string: "stratum://\(trimmed)"), let host = url.host {
            return host.lowercased()
        }

        let hostPort = trimmed.split(separator: "/").first ?? ""
        let host = hostPort.split(separator: ":").first ?? ""
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    static func displayName(for host: String) -> String {
        if host.contains("ocean") {
            return "Ocean"
        }
        if host.contains("public-pool") || host.contains("publicpool") {
            return "Public Pool"
        }
        if host.contains("parasite") {
            return "Parasite"
        }
        if host.contains("256foundation") {
            return "256 Foundation"
        }
        if host.contains("solo.ckpool") {
            return "Solo CK"
        }
        if host.contains("foundry") {
            return "Foundry USA"
        }
        if host.contains("antpool") {
            return "AntPool"
        }
        if host.contains("viabtc") {
            return "ViaBTC"
        }
        if host.contains("f2pool") {
            return "F2Pool"
        }
        if host.contains("braiins") || host.contains("slushpool") {
            return "Braiins Pool"
        }
        if host.contains("mara") {
            return "MARA Pool"
        }

        return host.replacingOccurrences(of: "www.", with: "")
    }

    static func logoName(for host: String) -> String? {
        if host.contains("ocean") {
            return "ocean"
        }
        if host.contains("public-pool") || host.contains("publicpool") {
            return "publicpool"
        }
        if host.contains("parasite") {
            return "parasite"
        }
        if host.contains("256foundation") {
            return "256-foundation"
        }
        return nil
    }

    static func poolSlug(for host: String) -> String? {
        if host.contains("ocean") {
            return "ocean"
        }
        if host.contains("public-pool") || host.contains("publicpool") {
            return "publicpool"
        }
        if host.contains("parasite") {
            return "parasite"
        }
        if host.contains("solo.ckpool") {
            return "solock"
        }
        if host.contains("foundry") {
            return "foundryusa"
        }
        if host.contains("antpool") {
            return "antpool"
        }
        if host.contains("viabtc") {
            return "viabtc"
        }
        if host.contains("f2pool") {
            return "f2pool"
        }
        if host.contains("braiins") || host.contains("slushpool") {
            return "braiinspool"
        }
        if host.contains("mara") {
            return "marapool"
        }
        return nil
    }
}
