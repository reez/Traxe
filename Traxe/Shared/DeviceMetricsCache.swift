import Foundation

struct CachedDeviceMetrics: Codable {
    let hashrate: Double
    let power: Double?
    let bestDifficulty: Double?
    let hostname: String?
    let poolURL: String?
    // Added: cache temperature (optional for backward compatibility)
    let temperature: Double?
    let lastUpdated: Date

    init(from metrics: DeviceMetrics) {
        self.hashrate = metrics.hashrate
        self.power = metrics.power
        self.bestDifficulty = metrics.bestDifficulty
        self.hostname = metrics.hostname
        self.poolURL = metrics.poolURL
        self.temperature = metrics.temperature
        self.lastUpdated = Date()
    }
}

extension DeviceMetrics {
    init(from cached: CachedDeviceMetrics) {
        self.init(
            hashrate: cached.hashrate,
            temperature: cached.temperature ?? 0.0,
            power: cached.power ?? 0.0,
            bestDifficulty: cached.bestDifficulty ?? 0.0,
            poolURL: cached.poolURL,
            hostname: cached.hostname
        )
    }
}

@MainActor
class DeviceMetricsCache {
    private let appGroupID = "group.matthewramsden.traxe"
    private let cacheKey = "cachedDeviceMetricsV1"
    private let schemaVersion = 1

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    func loadAll() -> [String: CachedDeviceMetrics] {
        guard let defaults = defaults,
            let data = defaults.data(forKey: cacheKey)
        else {
            return [:]
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([String: CachedDeviceMetrics].self, from: data)
        } catch {
            return [:]
        }
    }

    func saveAll(_ metricsByIP: [String: CachedDeviceMetrics]) {
        guard let defaults = defaults else { return }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(metricsByIP)
            defaults.set(data, forKey: cacheKey)
        } catch {
            // Silently fail - cache is not critical
        }
    }

    func prune(ips: [String]) {
        let currentCache = loadAll()
        let ipSet = Set(ips)
        let prunedCache = currentCache.filter { ipSet.contains($0.key) }

        if prunedCache.count != currentCache.count {
            saveAll(prunedCache)
        }
    }
}
