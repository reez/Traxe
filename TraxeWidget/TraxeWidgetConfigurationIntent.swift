import AppIntents
import Foundation
import WidgetKit

/// A saved miner as seen by the widget: read from the app-group cache, so the
/// query works without the app running.
struct WidgetMinerEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Miner")
    static let defaultQuery = WidgetMinerQuery()

    /// A persisted device identifier for new configurations. Older configurations
    /// may still store the miner's MAC or an IP address.
    var id: String
    var name: String
    /// Where the miner answers now, which is what the timeline fetches from and the
    /// key the shared cache uses.
    var ipAddress: String
    var macAddress: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(ipAddress)")
    }
}

struct WidgetMinerQuery: EntityQuery {
    private static let appGroupID = "group.matthewramsden.traxe"
    private static let savedDeviceRecordsKey = "savedDevices"
    private static let savedDevicesKey = "savedDeviceIPs"
    private static let savedDeviceMACAddressesKey = "savedDeviceMACAddresses"
    private static let deviceCacheKey = "cachedDeviceMetricsV2"

    private struct CachedNames: Codable {
        var hostname: String?
    }

    private struct StoredDeviceIdentifier: Decodable {
        let id: UUID?
        let ipAddress: String
    }

    static func savedMiners() -> [WidgetMinerEntity] {
        guard let defaults = UserDefaults(suiteName: appGroupID),
            let ipAddresses = defaults.array(forKey: savedDevicesKey) as? [String]
        else {
            return []
        }

        let macAddresses =
            defaults.dictionary(forKey: savedDeviceMACAddressesKey) as? [String: String] ?? [:]
        var persistentIDsByIPAddress: [String: String] = [:]
        if let data = defaults.data(forKey: savedDeviceRecordsKey),
            let devices = try? JSONDecoder().decode([StoredDeviceIdentifier].self, from: data)
        {
            for device in devices {
                if let id = device.id {
                    persistentIDsByIPAddress[device.ipAddress] = "device:\(id.uuidString)"
                }
            }
        }

        var hostnames: [String: String] = [:]
        if let data = defaults.data(forKey: deviceCacheKey),
            let cache = try? JSONDecoder().decode([String: CachedNames].self, from: data)
        {
            hostnames = cache.compactMapValues(\.hostname)
        }

        return ipAddresses.map { ip in
            WidgetMinerEntity(
                id: persistentIDsByIPAddress[ip] ?? macAddresses[ip] ?? ip,
                name: hostnames[ip] ?? ip,
                ipAddress: ip,
                macAddress: macAddresses[ip]
            )
        }
    }

    /// Widgets placed before the app learned a miner's MAC address store its IP address,
    /// so an unknown identifier is followed through the alias the app records when
    /// DHCP moves the miner. The stored identifier stays on the entity.
    func entities(for identifiers: [String]) async throws -> [WidgetMinerEntity] {
        let miners = Self.savedMiners()
        let aliases = SavedDeviceAddressAliases.appGroup()
        let minerIdentifiers = miners.map {
            (id: $0.id, macAddress: $0.macAddress, ipAddress: $0.ipAddress)
        }

        return identifiers.compactMap { identifier in
            guard let index = SavedDeviceAddressAliases.indexOfMiner(
                identifiedBy: identifier,
                in: minerIdentifiers,
                aliases: aliases
            ) else {
                return nil
            }
            var miner = miners[index]
            miner.id = identifier
            return miner
        }
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
