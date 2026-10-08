import Foundation
import Observation

private struct CachedDeviceMetrics: Codable {
    var hashrate: Double
    var power: Double?
    var bestDifficulty: Double?
    var hostname: String?
    var poolURL: String?
    var temperature: Double?
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
    var isReachable: Bool?
    var isHashrateKnown: Bool?
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
}

struct WatchMinerSummary: Identifiable, Hashable {
    let id: String  // IP address
    let name: String
    let ipAddress: String
    let hashrateValue: String
    let hashrateUnit: String
    let lastUpdated: Date?
    var statusText: String = ""

    static func sample(id: String, name: String, ip: String, hashrate: Double) -> WatchMinerSummary
    {
        let formatted = hashrate.formattedHashRateWithUnit()
        return WatchMinerSummary(
            id: id,
            name: name,
            ipAddress: ip,
            hashrateValue: formatted.value,
            hashrateUnit: formatted.unit,
            lastUpdated: Date()
        )
    }
}

@Observable
@MainActor
final class HashrateViewModel {
    private let appGroupID = "group.matthewramsden.traxe"
    private let deviceCacheKey = "cachedDeviceMetricsV2"
    private let legacyDataKey = "lastKnownWidgetData"

    var totalHashrateValue: String = "--"
    var totalHashrateUnit: String = ""
    var totalLastUpdated: Date?
    var metricStatus: String = "No readings yet"
    var miners: [WatchMinerSummary] = []

    func start() async {
        await refresh()
        WatchSessionManager.shared.requestHashrateUpdate()
    }

    func refresh() async {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            resetState()
            WatchSessionManager.shared.requestHashrateUpdate()
            return
        }

        if let data = defaults.data(forKey: deviceCacheKey) {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let cache = try decoder.decode([String: CachedDeviceMetrics].self, from: data)
                if !cache.isEmpty {
                    applyCache(cache)
                    return
                }
            } catch {
                // Ignore corrupt cache and fall back to legacy data
            }
        }

        if let legacy = defaults.dictionary(forKey: legacyDataKey),
            let hashrateString = legacy["hashrate"] as? String
        {
            applyLegacyData(
                legacyHashrate: hashrateString,
                unit: legacy["unit"] as? String,
                date: legacy["cachedDate"] as? Date
            )
            WatchSessionManager.shared.requestHashrateUpdate()
            return
        }

        resetState()
        WatchSessionManager.shared.requestHashrateUpdate()
    }

    private func applyCache(_ cache: [String: CachedDeviceMetrics]) {
        let deviceCount =
            UserDefaults(suiteName: appGroupID)?.integer(forKey: "fleetDeviceCount") ?? cache.count
        let snapshot = FleetMetricSnapshot.make(
            readings: cache.map { $0.value.reading(id: $0.key) },
            totalDevices: deviceCount
        )
        let formattedTotal = snapshot.totalHashrate?.formattedHashRateWithUnit()
        totalHashrateValue = formattedTotal?.value ?? "--"
        totalHashrateUnit = formattedTotal?.unit ?? ""
        totalLastUpdated = snapshot.measuredAt
        metricStatus = snapshot.statusText

        let summariesWithHashrate = cache.map {
            (ip, metrics) -> (summary: WatchMinerSummary, hashrate: Double) in
            let formatted =
                metrics.isHashrateKnown == false
                ? nil : metrics.hashrate.formattedHashRateWithUnit()
            let rowStatus = snapshot.rowStatusText(for: metrics.reading(id: ip))
            let displayName = metrics.hostname?.isEmpty == false ? (metrics.hostname ?? ip) : ip
            let summary = WatchMinerSummary(
                id: ip,
                name: displayName,
                ipAddress: ip,
                hashrateValue: formatted?.value ?? "--",
                hashrateUnit: formatted?.unit ?? "",
                lastUpdated: metrics.measurementDate,
                statusText: rowStatus
            )
            return (summary, metrics.hashrate)
        }

        miners =
            summariesWithHashrate
            .sorted { $0.hashrate > $1.hashrate }
            .map(\.summary)
    }

    private func applyLegacyData(legacyHashrate: String, unit: String?, date: Date?) {
        totalHashrateValue = legacyHashrate
        totalHashrateUnit = unit ?? ""
        totalLastUpdated = date
        metricStatus = "Last known · stale"
        miners = []
    }

    private func resetState() {
        totalHashrateValue = "--"
        totalHashrateUnit = ""
        totalLastUpdated = nil
        metricStatus = "No readings yet"
        miners = []
    }
}

extension HashrateViewModel {
    nonisolated static func previewModel() -> HashrateViewModel {
        MainActor.assumeIsolated {
            let model = HashrateViewModel()
            let miner1Value = 495.1
            let miner2Value = 312.7
            let totalFormatted = (miner1Value + miner2Value).formattedHashRateWithUnit()
            model.totalHashrateValue = totalFormatted.value
            model.totalHashrateUnit = totalFormatted.unit
            model.totalLastUpdated = Date()
            model.miners = [
                WatchMinerSummary.sample(
                    id: "192.168.4.27",
                    name: "bitaxe",
                    ip: "192.168.4.27",
                    hashrate: miner1Value
                ),
                WatchMinerSummary.sample(
                    id: "192.168.4.42",
                    name: "nerdqaxe",
                    ip: "192.168.4.42",
                    hashrate: miner2Value
                ),
            ]
            return model
        }
    }
}
