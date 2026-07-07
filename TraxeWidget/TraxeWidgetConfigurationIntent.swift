import AppIntents
import Foundation
import WidgetKit

/// A saved miner as seen by the widget: read from the app-group cache, so the
/// query works without the app running.
struct WidgetMinerEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Miner")
    static let defaultQuery = WidgetMinerQuery()

    /// The miner's IP address — same identifier the app and cache key on.
    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(id)")
    }
}

struct WidgetMinerQuery: EntityQuery {
    private static let appGroupID = "group.matthewramsden.traxe"
    private static let savedDevicesKey = "savedDeviceIPs"
    private static let deviceCacheKey = "cachedDeviceMetricsV2"

    private struct CachedNames: Codable {
        var hostname: String?
    }

    static func savedMiners() -> [WidgetMinerEntity] {
        guard let defaults = UserDefaults(suiteName: appGroupID),
            let ipAddresses = defaults.array(forKey: savedDevicesKey) as? [String]
        else {
            return []
        }

        var hostnames: [String: String] = [:]
        if let data = defaults.data(forKey: deviceCacheKey),
            let cache = try? JSONDecoder().decode([String: CachedNames].self, from: data)
        {
            hostnames = cache.compactMapValues(\.hostname)
        }

        return ipAddresses.map { ip in
            WidgetMinerEntity(id: ip, name: hostnames[ip] ?? ip)
        }
    }

    func entities(for identifiers: [String]) async throws -> [WidgetMinerEntity] {
        Self.savedMiners().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetMinerEntity] {
        Self.savedMiners()
    }
}

struct SelectMinerIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Select Miner"
    static let description = IntentDescription(
        "Choose a single miner to track, or leave empty to show the whole fleet."
    )

    @Parameter(title: "Miner")
    var miner: WidgetMinerEntity?
}
