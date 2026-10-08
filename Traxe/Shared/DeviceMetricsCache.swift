import Foundation

struct CachedDeviceMetrics: Codable, Sendable {
    var hashrate: Double
    var power: Double?
    var bestDifficulty: Double?
    var hostname: String?
    var poolURL: String?
    var blockHeight: Int?
    var networkDifficulty: Double?
    var isMiningPaused: Bool?
    var isHashrateKnown: Bool?
    var isTemperatureKnown: Bool?
    var isMiningPausedKnown: Bool?
    // Added: cache temperature (optional for backward compatibility)
    var temperature: Double?
    var macAddress: String?
    var lastUpdated: Date {
        didSet { lastUpdatedReferenceTime = lastUpdated.timeIntervalSinceReferenceDate }
    }
    // Keep the legacy ISO8601 date for older readers. Its whole-second encoding
    // cannot order samples from separate refreshes within the same second.
    var lastUpdatedReferenceTime: TimeInterval?
    var measurementDate: Date {
        guard let lastUpdatedReferenceTime, lastUpdatedReferenceTime.isFinite else {
            return lastUpdated
        }
        return Date(timeIntervalSinceReferenceDate: lastUpdatedReferenceTime)
    }
    // Nil preserves the behavior of caches written before reachability was recorded.
    var isReachable: Bool?
    var isHashrateReporting: Bool?
    var observedAt: Date?
    var isIncludedInLastKnownTotal: Bool?

    func reading(id: String) -> FleetMetricSnapshot.Reading {
        .init(
            id: id,
            hashrate: isHashrateKnown == false ? nil : hashrate,
            power: power,
            measuredAt: measurementDate,
            isReachable: isReachable,
            isHashrateReporting: isHashrateReporting,
            observedAt: observedAt,
            isIncludedInLastKnownTotal: isIncludedInLastKnownTotal
        )
    }

    init(from metrics: DeviceMetrics, isReachable: Bool? = nil) {
        self.hashrate = metrics.hashrate
        self.power = metrics.power
        self.bestDifficulty = metrics.bestDifficulty
        self.hostname = metrics.hostname
        self.poolURL = metrics.poolURL
        self.blockHeight = metrics.blockHeight
        self.networkDifficulty = metrics.networkDifficulty
        self.isMiningPaused = metrics.isMiningPaused
        self.isHashrateKnown = metrics.isHashrateKnown
        self.isTemperatureKnown = metrics.isTemperatureKnown
        self.isMiningPausedKnown = metrics.isMiningPausedKnown
        self.temperature = metrics.temperature
        self.macAddress = SavedDevice.normalizedMACAddress(metrics.macAddress)
        self.lastUpdated = metrics.timestamp
        self.lastUpdatedReferenceTime = metrics.timestamp.timeIntervalSinceReferenceDate
        self.isReachable = isReachable
        self.isHashrateReporting = metrics.isHashrateKnown
        self.observedAt = isReachable == nil ? nil : Date()
    }
}

extension DeviceMetrics {
    init(from cached: CachedDeviceMetrics) {
        self.init(
            hashrate: cached.hashrate,
            temperature: cached.temperature ?? 0.0,
            power: cached.power ?? 0.0,
            timestamp: cached.measurementDate,
            bestDifficulty: cached.bestDifficulty ?? 0.0,
            poolURL: cached.poolURL,
            hostname: cached.hostname,
            blockHeight: cached.blockHeight,
            networkDifficulty: cached.networkDifficulty,
            isHashrateKnown: cached.isHashrateKnown ?? true,
            isTemperatureKnown: cached.isTemperatureKnown ?? false,
            isMiningPaused: cached.isMiningPaused ?? false,
            isMiningPausedKnown: cached.isMiningPausedKnown ?? false,
            macAddress: cached.macAddress
        )
    }
}

@MainActor
class DeviceMetricsCache {
    // Bump key to drop previously cached (pre-normalization) hashrate values.
    private let cacheKey = "cachedDeviceMetricsV2"
    private let schemaVersion = 1
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: "group.matthewramsden.traxe")) {
        self.defaults = defaults
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
