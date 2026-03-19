import Foundation

struct WeeklyRecapPoolAllocation: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let logoName: String?
    let configuredPercent: Double?
    let estimatedHashrate: Double
}

enum WeeklyRecapPoolAllocationBuilder {
    private struct ParsedPoolSegment: Sendable {
        let displayName: String
        let logoName: String?
        let percent: Double?
    }

    static func build(from poolDisplayName: String?, totalHashrate: Double)
        -> [WeeklyRecapPoolAllocation]
    {
        let segments = parseSegments(from: poolDisplayName)
        guard !segments.isEmpty else { return [] }

        let weights = normalizedWeights(for: segments)
        let referenceHashrate = max(totalHashrate, 0)

        return zip(segments.indices, segments).map { index, segment in
            let allocationID = [
                segment.displayName.lowercased(),
                segment.logoName?.lowercased() ?? "none",
            ]
            .joined(separator: "|")

            return WeeklyRecapPoolAllocation(
                id: allocationID,
                name: segment.displayName,
                logoName: segment.logoName,
                configuredPercent: segment.percent,
                estimatedHashrate: referenceHashrate * weights[index]
            )
        }
    }

    static func buildFleetTotals(
        from sources: [(poolDisplayName: String?, totalHashrate: Double)]
    ) -> [WeeklyRecapPoolAllocation] {
        var totalsByID: [String: WeeklyRecapPoolAllocation] = [:]

        for source in sources {
            for allocation in build(
                from: source.poolDisplayName,
                totalHashrate: source.totalHashrate
            ) {
                if let existing = totalsByID[allocation.id] {
                    totalsByID[allocation.id] = WeeklyRecapPoolAllocation(
                        id: existing.id,
                        name: existing.name,
                        logoName: existing.logoName,
                        configuredPercent: nil,
                        estimatedHashrate: existing.estimatedHashrate + allocation.estimatedHashrate
                    )
                } else {
                    totalsByID[allocation.id] = allocation
                }
            }
        }

        return totalsByID.values.sorted { lhs, rhs in
            if lhs.estimatedHashrate == rhs.estimatedHashrate {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.estimatedHashrate > rhs.estimatedHashrate
        }
    }

    private static func parseSegments(from poolDisplayName: String?) -> [ParsedPoolSegment] {
        guard let poolDisplayName else { return [] }

        return
            poolDisplayName
            .components(separatedBy: "\u{2022}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { segment in
                let trimmedSegment = removingTrailingPercent(from: segment)
                let host = normalizedHost(from: trimmedSegment)
                return ParsedPoolSegment(
                    displayName: displayName(for: trimmedSegment, host: host),
                    logoName: host.flatMap(poolLogoName(for:)),
                    percent: trailingPercent(in: segment)
                )
            }
    }

    private static func normalizedWeights(for segments: [ParsedPoolSegment]) -> [Double] {
        guard !segments.isEmpty else { return [] }
        if segments.count == 1 {
            return [1]
        }

        let explicitPercents = segments.compactMap(\.percent)
        if explicitPercents.count == segments.count {
            let total = explicitPercents.reduce(0, +)
            if total > 0 {
                return explicitPercents.map { $0 / total }
            }
        }

        let equalWeight = 1 / Double(segments.count)
        return Array(repeating: equalWeight, count: segments.count)
    }

    private static func trailingPercent(in text: String) -> Double? {
        guard
            let range = text.range(
                of: #"\((\d+(?:\.\d+)?)%\)\s*$"#,
                options: .regularExpression
            )
        else {
            return nil
        }

        let percentText = String(text[range])
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(percentText)
    }

    private static func removingTrailingPercent(from text: String) -> String {
        text
            .replacingOccurrences(
                of: #"\s*\(\d+(?:\.\d+)?%\)\s*$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func displayName(for rawName: String, host: String?) -> String {
        guard let host else { return rawName }

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

        return host.replacingOccurrences(of: "www.", with: "")
    }

    private static func poolLogoName(for host: String) -> String? {
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

    private static func normalizedHost(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
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
}
