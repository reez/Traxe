import AppIntents
import Foundation
import SwiftUI
import WidgetKit

#if canImport(WatchConnectivity)
    import WatchConnectivity
#endif

// Color extension for widget target
extension Color {
    static let traxeGold = Color(red: 218 / 255, green: 165 / 255, blue: 32 / 255)
}

// Minimal copy of the app's cached device metrics structure for the widget target
// Stored under the same app group key so both app and widget stay in sync.
private struct CachedDeviceMetrics: Codable, Sendable {
    var hashrate: Double
    var power: Double?
    var bestDifficulty: Double?
    var hostname: String?
    var poolURL: String?
    var isMiningPaused: Bool?
    var isHashrateKnown: Bool?
    var isTemperatureKnown: Bool?
    var isMiningPausedKnown: Bool?
    // Include temperature so widget preserves it in the shared cache
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
    var isHashrateReporting: Bool?
    var observedAt: Date?
    var isIncludedInLastKnownTotal: Bool?

    func reading(id: String) -> FleetMetricSnapshot.Reading {
        .init(id: id, hashrate: isHashrateKnown == false ? nil : hashrate,
              power: power, measuredAt: measurementDate, isReachable: isReachable,
              isHashrateReporting: isHashrateReporting, observedAt: observedAt,
              isIncludedInLastKnownTotal: isIncludedInLastKnownTotal)
    }
}

struct Provider: AppIntentTimelineProvider {
    let appGroupID = "group.matthewramsden.traxe"
    let savedDevicesKey = "savedDeviceIPs"
    let cachedDataKey = "lastKnownWidgetData"
    let deviceCacheKey = "cachedDeviceMetricsV2"

    private func getNetworkService() -> NetworkService {
        return NetworkService()
    }

    // MARK: - Shared per-device cache helpers
    private func loadDeviceMetricsCache() -> [String: CachedDeviceMetrics] {
        guard let defaults = UserDefaults(suiteName: appGroupID),
            let data = defaults.data(forKey: deviceCacheKey)
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

    private func saveDeviceMetricsCache(_ metricsByIP: [String: CachedDeviceMetrics]) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(metricsByIP)
            defaults.set(data, forKey: deviceCacheKey)
        } catch {
            // Best-effort cache write
        }
        #if canImport(WatchConnectivity)
            pushUpdateToWatch(metricsByIP)
        #endif
    }

    private func cacheLastKnownData(hashrate: String, totalDevices: Int, successfulFetches: Int) {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupID) else { return }
        let cachedData: [String: Any] = [
            "hashrate": hashrate,
            "totalDevices": totalDevices,
            "successfulFetches": successfulFetches,
            "cachedDate": Date(),
        ]
        sharedDefaults.set(cachedData, forKey: cachedDataKey)
    }

    private func getLastKnownData() -> (
        hashrate: String, totalDevices: Int, successfulFetches: Int, cachedDate: Date
    )? {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupID),
            let cachedData = sharedDefaults.dictionary(forKey: cachedDataKey),
            let hashrate = cachedData["hashrate"] as? String,
            let totalDevices = cachedData["totalDevices"] as? Int,
            let successfulFetches = cachedData["successfulFetches"] as? Int,
            let cachedDate = cachedData["cachedDate"] as? Date
        else {
            return nil
        }
        return (
            hashrate: hashrate, totalDevices: totalDevices, successfulFetches: successfulFetches,
            cachedDate: cachedDate
        )
    }

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), hashrate: "--", isPlaceholder: true, lastUpdated: nil)
    }

    func snapshot(for configuration: SelectMinerIntent, in context: Context) async -> SimpleEntry {
        // Prefer real cached data so the gallery preview mirrors the user's fleet;
        // fall back to a representative fleet for first-time installs.
        let cache = loadDeviceMetricsCache()
        if !cache.isEmpty {
            let snapshot = FleetMetricSnapshot.make(
                readings: cache.map { $0.value.reading(id: $0.key) },
                totalDevices: (UserDefaults(suiteName: appGroupID)?.array(forKey: savedDevicesKey) as? [String])?.count ?? cache.count
            )
            let deviceIDs = Array(cache.keys)
            let reachableDeviceIDs = snapshot.reportingDeviceIDs
            let pausedDeviceIDs = Set(
                cache.compactMap { deviceID, metrics in
                    metrics.isMiningPausedKnown == true && metrics.isMiningPaused == true
                        ? deviceID : nil
                }
            )
            return SimpleEntry(
                date: Date(),
                hashrate: snapshot.totalHashrate?.formatted(
                    .number.grouping(.never).precision(.fractionLength(1))
                ) ?? "--",
                totalDevices: snapshot.totalDevices,
                successfulFetches: reachableDeviceIDs.count,
                lastUpdated: snapshot.measuredAt,
                metricStatus: snapshot.statusText,
                compactMetricStatus: snapshot.compactStatusText,
                fleetStatus: WidgetFleetStatus.make(
                    deviceIDs: deviceIDs,
                    respondedDeviceIDs: reachableDeviceIDs,
                    deviceIDsWithMetrics: snapshot.includedDeviceIDs,
                    pausedDeviceIDs: pausedDeviceIDs,
                    knownHashratesByDeviceID: cache.compactMapValues {
                        $0.isHashrateKnown == false ? nil : $0.hashrate
                    }
                )
            )
        }
        return SimpleEntry(
            date: Date(),
            hashrate: "15400.0",
            totalDevices: 7,
            successfulFetches: 6,
            lastUpdated: Date(),
            fleetStatus: WidgetFleetStatus(
                total: 7,
                online: 4,
                paused: 1,
                offline: 1,
                unknown: 1
            )
        )
    }

    func timeline(
        for configuration: SelectMinerIntent,
        in context: Context
    ) async -> Timeline<SimpleEntry> {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupID),
            let initialIPAddresses = sharedDefaults.array(forKey: savedDevicesKey) as? [String],
            !initialIPAddresses.isEmpty
        else {
            let entry = SimpleEntry(
                date: Date(),
                hashrate: "Setup",
                totalDevices: 0,
                lastUpdated: nil
            )
            return Timeline(
                entries: [entry],
                policy: .after(Date().addingTimeInterval(60 * 15))
            )
        }

            let currentDate = Date()
            let refreshDate = Calendar.current.date(byAdding: .minute, value: 10, to: currentDate)!
            let networkService = getNetworkService()
            let initialState = WidgetFleetRefresh<CachedDeviceMetrics>.State(
                ipAddresses: initialIPAddresses,
                savedDevicesData: sharedDefaults.data(forKey: "savedDevices"),
                metricsByIP: loadDeviceMetricsCache()
            )
            let refresh = await WidgetFleetRefresh<CachedDeviceMetrics>.run(
                initialState: initialState,
                fetch: { ip in
                    let telemetry = try await networkService.fetchMinerTelemetry(
                        ipAddressOverride: ip
                    )
                    return .init(hashrate: telemetry.hashrate, temperature: telemetry.temp)
                },
                loadCurrentState: {
                    .init(
                        ipAddresses: sharedDefaults.array(forKey: savedDevicesKey) as? [String] ?? [],
                        savedDevicesData: sharedDefaults.data(forKey: "savedDevices"),
                        metricsByIP: loadDeviceMetricsCache()
                    )
                }
            )
            let ipAddresses = refresh.state.ipAddresses
            let perDeviceCache = refresh.state.metricsByIP
            let fetchedHashrates = refresh.responses.compactMapValues(\.hashrate)
            let fetchedTemps = refresh.responses.compactMapValues(\.temperature)
            let respondedIPAddresses = Set(refresh.responses.keys)
            guard !ipAddresses.isEmpty else {
                saveDeviceMetricsCache([:])
                let entry = SimpleEntry(
                    date: Date(), hashrate: "Setup", totalDevices: 0, lastUpdated: nil
                )
                return Timeline(entries: [entry], policy: .after(refreshDate))
            }

            // Merge: prefer fresh values; fallback to cached per device; prune to current IPs
            let currentIPs = Set(ipAddresses)
            var merged: [String: CachedDeviceMetrics] = refresh.canApplyResponses
                ? [:] : perDeviceCache.filter { currentIPs.contains($0.key) }
            let now = Date()
            for ip in ipAddresses where refresh.canApplyResponses {
                if let fresh = fetchedHashrates[ip] {
                    var entry =
                        perDeviceCache[ip]
                        ?? CachedDeviceMetrics(
                            hashrate: fresh,
                            power: 0.0,  // write non-nil default to keep cache clean
                            bestDifficulty: 0.0,  // write non-nil default to keep cache clean
                            hostname: nil,
                            poolURL: nil,
                            isMiningPaused: nil,
                            isHashrateKnown: true,
                            isTemperatureKnown: false,
                            isMiningPausedKnown: false,
                            temperature: nil,
                            lastUpdated: now
                        )
                    entry.hashrate = fresh
                    entry.isHashrateKnown = true
                    if let t = fetchedTemps[ip] {
                        entry.temperature = t
                        entry.isTemperatureKnown = true
                    }
                    entry.lastUpdated = now
                    entry.isReachable = true
                    entry.isHashrateReporting = true
                    entry.observedAt = now
                    merged[ip] = entry
                } else if var cached = perDeviceCache[ip] {
                    cached.isReachable = respondedIPAddresses.contains(ip)
                    cached.isHashrateReporting = false
                    cached.observedAt = now
                    merged[ip] = cached
                } else if respondedIPAddresses.contains(ip) {
                    merged[ip] = CachedDeviceMetrics(
                        hashrate: 0, power: nil, bestDifficulty: nil, hostname: nil,
                        poolURL: nil, isMiningPaused: nil, isHashrateKnown: false,
                        isTemperatureKnown: false, isMiningPausedKnown: false,
                        temperature: fetchedTemps[ip], lastUpdated: now,
                        lastUpdatedReferenceTime: now.timeIntervalSinceReferenceDate,
                        isReachable: true, isHashrateReporting: false, observedAt: now
                    )
                }
            }

            // Failed requests preserve their measurements. Reporting totals only
            // include hash rates actually returned in this observation.
            let snapshot = FleetMetricSnapshot.make(
                readings: ipAddresses.map { ip in
                    merged[ip]?.reading(id: ip) ?? .init(
                        id: ip, hashrate: nil, measuredAt: now,
                        isReachable: respondedIPAddresses.contains(ip)
                    )
                },
                totalDevices: ipAddresses.count,
                referenceDate: now
            )
            let successfulFetches = snapshot.reportingDeviceIDs.count
            let displayHashrate = snapshot.totalHashrate?.formatted(
                .number.grouping(.never).precision(.fractionLength(1))
            ) ?? "--"
            let pausedDeviceIDs = Set(
                merged.compactMap { deviceID, metrics in
                    metrics.isMiningPausedKnown == true && metrics.isMiningPaused == true
                        ? deviceID : nil
                }
            )
            let fleetStatus = WidgetFleetStatus.make(
                deviceIDs: ipAddresses,
                respondedDeviceIDs: snapshot.reportingDeviceIDs,
                deviceIDsWithMetrics: snapshot.includedDeviceIDs,
                pausedDeviceIDs: pausedDeviceIDs,
                knownHashratesByDeviceID: merged.compactMapValues {
                    $0.isHashrateKnown == false ? nil : $0.hashrate
                }
            )

            // Preserve exactly this total if the next refresh cannot reach any
            // miners, rather than re-adding recently failed miners from cache.
            for ip in merged.keys {
                merged[ip]?.isIncludedInLastKnownTotal = snapshot.includedDeviceIDs.contains(ip)
            }
            // Save merged per-device cache for app + widget consistency
            saveDeviceMetricsCache(merged)

            // Piggyback miner health alerts on this refresh (no-op unless the
            // user enabled them in Settings and granted notification permission).
            if refresh.canApplyResponses {
                await MinerAlertEvaluator.evaluate(
                    ipAddresses: ipAddresses,
                    respondedIPAddresses: respondedIPAddresses,
                    baselineReachableIPAddresses: Set(
                        perDeviceCache.compactMap { ipAddress, metrics in
                            currentDate.timeIntervalSince(metrics.measurementDate) <= 30 * 60
                                ? ipAddress : nil
                        }
                    ),
                    fetchedTemps: fetchedTemps,
                    hostnames: merged.compactMapValues(\.hostname)
                )
            }

            // Also keep lastKnownWidgetData for backward compatibility
            if snapshot.totalHashrate != nil, !snapshot.isStale {
                cacheLastKnownData(
                    hashrate: displayHashrate,
                    totalDevices: ipAddresses.count,
                    successfulFetches: successfulFetches
                )
            }

            // A configured miner narrows the displayed numbers; the fetch and the
            // shared cache above always cover the whole fleet.
            if let selected = configuration.miner {
                let selectedMetrics = merged[selected.ipAddress]
                var selectedReading = selectedMetrics?.reading(id: selected.ipAddress) ?? .init(
                    id: selected.ipAddress, hashrate: nil, measuredAt: now,
                    isReachable: respondedIPAddresses.contains(selected.ipAddress)
                )
                // An individually selected miner keeps its own last reading even
                // when that miner was excluded from the last fleet total.
                selectedReading.isIncludedInLastKnownTotal = nil
                let selectedSnapshot = FleetMetricSnapshot.make(
                    readings: [selectedReading],
                    totalDevices: 1,
                    referenceDate: now
                )
                let entry = SimpleEntry(
                    date: currentDate,
                    hashrate: selectedSnapshot.totalHashrate?.formatted(
                        .number.grouping(.never).precision(.fractionLength(1))
                    ) ?? "--",
                    totalDevices: 1,
                    successfulFetches: selectedSnapshot.reportingDeviceIDs.count,
                    lastUpdated: selectedSnapshot.measuredAt,
                    metricStatus: selectedSnapshot.statusText,
                    compactMetricStatus: selectedSnapshot.compactStatusText,
                    minerName: selectedMetrics?.hostname ?? selected.name,
                    fleetStatus: WidgetFleetStatus.make(
                        deviceIDs: [selected.ipAddress],
                        respondedDeviceIDs: snapshot.reportingDeviceIDs,
                        deviceIDsWithMetrics: snapshot.includedDeviceIDs,
                        pausedDeviceIDs: pausedDeviceIDs,
                        knownHashratesByDeviceID: merged.compactMapValues {
                            $0.isHashrateKnown == false ? nil : $0.hashrate
                        }
                    )
                )
                return Timeline(entries: [entry], policy: .after(refreshDate))
            }

            let entry = SimpleEntry(
                date: currentDate,
                hashrate: displayHashrate,
                totalDevices: ipAddresses.count,
                successfulFetches: successfulFetches,
                lastUpdated: snapshot.measuredAt,
                metricStatus: snapshot.statusText,
                compactMetricStatus: snapshot.compactStatusText,
                fleetStatus: fleetStatus
            )
            return Timeline(entries: [entry], policy: .after(refreshDate))
    }
}

#if canImport(WatchConnectivity)
    private func pushUpdateToWatch(_ metrics: [String: CachedDeviceMetrics]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.activationState != .activated {
            session.activate()
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(metrics) else { return }

        let deviceCount = (UserDefaults(suiteName: "group.matthewramsden.traxe")?
            .array(forKey: "savedDeviceIPs") as? [String])?.count ?? metrics.count
        let snapshot = FleetMetricSnapshot.make(
            readings: metrics.map { $0.value.reading(id: $0.key) },
            totalDevices: deviceCount
        )
        var payload: [String: Any] = ["cacheData": data, "deviceCount": deviceCount]
        if let totalHashrate = snapshot.totalHashrate { payload["totalHashrate"] = totalHashrate }
        if let measuredAt = snapshot.measuredAt { payload["lastUpdated"] = measuredAt }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }

        do {
            try session.updateApplicationContext(payload)
        } catch {
            // Ignore failures; transferUserInfo below will still deliver when possible.
        }

        session.transferCurrentComplicationUserInfo(payload)
        session.transferUserInfo(payload)
    }
#endif

struct SimpleEntry: TimelineEntry {
    let date: Date
    let hashrate: String
    var totalDevices: Int = 0
    var successfulFetches: Int = 0
    var isPlaceholder: Bool = false
    let lastUpdated: Date?
    var metricStatus: String = ""
    var compactMetricStatus: String = ""
    /// Set when the widget is configured to a single miner.
    var minerName: String? = nil
    var fleetStatus: WidgetFleetStatus = .empty
}

struct TraxeWidgetEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily
    @Environment(\.widgetRenderingMode) var renderingMode
    var entry: Provider.Entry

    var body: some View {

        switch widgetFamily {

        case .accessoryCircular:

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.compactMetricStatus.isEmpty ? "HASH RATE" : entry.compactMetricStatus)
                    //                    .font(.caption2)
                    .font(.custom("system", size: 10))
                    //                        .foregroundStyle(.primary)
                    .fontDesign(.rounded)
                    .minimumScaleFactor(0.25)

                let (valueText, unitText) = Self.formatHashrate(entry.hashrate)

                Text(valueText)
                    //.font(.caption2)//.font(.title3)
                    .fontWeight(.bold)
                    .fontDesign(.rounded)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .redacted(
                        reason: (entry.isPlaceholder || entry.hashrate == "Error")
                            ? .placeholder : []
                    )

                Text(unitText)
                    .font(.custom("system", size: 10))
                    //                    .font(.caption2)
                    //                        .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .fontDesign(.rounded)
                    .minimumScaleFactor(0.35)
            }

        case .accessoryInline:

            HStack {
                Image(systemName: "poweroutlet.type.a.fill")
                let (valueText, unitText) = Self.formatHashrate(entry.hashrate)
                //
                //                Text(valueText)
                //                    .font(.title3)
                //                    .fontWeight(.bold)
                //                    .fontDesign(.rounded)
                //                    .minimumScaleFactor(0.6)
                //                    .lineLimit(1)
                //                    .contentTransition(.numericText())
                //                    .redacted(reason: (entry.isPlaceholder || entry.hashrate == "Error") ? .placeholder : [])
                //
                //                Text(unitText)
                //                    .font(.caption2)
                ////                        .fontWeight(.medium)
                ////                        .foregroundStyle(.secondary)
                //                    .fontDesign(.rounded)
                //                    .minimumScaleFactor(0.5)

                Text("\(valueText) \(unitText) \(entry.compactMetricStatus)")
                    .fontDesign(.rounded)
                    .minimumScaleFactor(0.5)

            }

        case .accessoryRectangular:

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    let (valueText, unitText) = Self.formatHashrate(entry.hashrate)
                    HStack {
                        Text(entry.compactMetricStatus.isEmpty ? "HASH RATE" : entry.compactMetricStatus)
                            .font(.caption2)
                            //                        .foregroundStyle(.primary)
                            .fontDesign(.rounded)
                            .minimumScaleFactor(0.5)
                        //                        Spacer()
                        Text(unitText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fontDesign(.rounded)
                            .minimumScaleFactor(0.5)
                    }

                    HStack(alignment: .center) {

                        Text(valueText)
                            .font(.title3)
                            .fontWeight(.bold)
                            .fontDesign(.rounded)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                            .redacted(
                                reason: (entry.isPlaceholder || entry.hashrate == "Error")
                                    ? .placeholder : []
                            )

                        //                            Text(unitText)
                        //                                .font(.caption2)
                        //                                .foregroundStyle(.secondary)
                        //                                .fontDesign(.rounded)
                        //                                .minimumScaleFactor(0.5)

                    }

                    //                    Spacer()

                    //                    Text("at \(entry.lastUpdated ?? entry.date, style: .time)")
                    //                        .font(.caption2)
                    //                        .foregroundStyle(.tertiary)
                    //                        .fontDesign(.rounded)

                }
                //        .padding(.vertical, 10)
                //                .padding(.all, 10.0)
                Spacer()
            }
        //            .padding()

        case .systemSmall:

            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text((entry.minerName ?? "Hash Rate").uppercased())
                        .font(.caption2)
                        .foregroundStyle(Color.traxeGold)
                        .fontDesign(.rounded)
                        .lineLimit(1)

                    let (valueText, unitText) = Self.formatHashrate(entry.hashrate)

                    Text(valueText)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                        .redacted(
                            reason: (entry.isPlaceholder || entry.hashrate == "Error")
                                ? .placeholder : []
                        )

                    Text(unitText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .fontDesign(.rounded)

                    Spacer()

                    Text(entry.metricStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let lastUpdated = entry.lastUpdated {
                        Text("Last reading \(lastUpdated, style: .relative) ago")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                }
                //        .padding(.vertical, 10)
                .padding(.all, 10.0)
                Spacer()
            }

        // `.systemLarge` and `.systemExtraLargePortrait` on iOS 27 both land here —
        // routing the new family through `default` avoids referencing the iOS 27
        // enum case symbol, so no compiler gating is needed in this switch.
        default:
            let (valueText, unitText) = Self.formatHashrate(entry.hashrate)
            LargeFleetWidgetView(
                minerName: entry.minerName,
                hashrateValue: valueText,
                hashrateUnit: unitText,
                updatedAt: entry.lastUpdated,
                isRedacted: entry.isPlaceholder || entry.hashrate == "Error",
                status: entry.fleetStatus,
                metricStatus: entry.metricStatus
            )

        }

    }

    private static func formatHashrate(_ hashrateString: String) -> (value: String, unit: String) {
        if hashrateString == "--" || hashrateString == "Error" {
            return (value: hashrateString, unit: "")
        }

        let isPartial = hashrateString.hasSuffix("+")
        let numericString = isPartial ? String(hashrateString.dropLast()) : hashrateString

        let trimmedString = numericString.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        let parsedValue =
            formatter.number(from: trimmedString)?.doubleValue
            ?? Double(trimmedString)
        guard let value = parsedValue else {
            return (value: hashrateString, unit: "")
        }

        if value >= 1000 {
            let teraValue = value / 1000
            return (
                value: teraValue.formatted(.number.precision(.fractionLength(1))),
                unit: "TH/s"
            )
        } else {
            return (
                value: value.formatted(.number.precision(.fractionLength(1))),
                unit: "GH/s"
            )
        }
    }
}

struct TraxeWidget: Widget {
    let kind: String = "TraxeWidget"
    @Environment(\.colorScheme) var colorScheme

    private var supportedFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [
            .accessoryCircular, .accessoryInline, .accessoryRectangular,
            .systemSmall, .systemLarge,
        ]
        #if compiler(>=6.4)
            // Full-page home screen widget, new in iOS 27.
            if #available(iOS 27.0, *) {
                families.append(.systemExtraLargePortrait)
            }
        #endif
        return families
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectMinerIntent.self,
            provider: Provider()
        ) { entry in
            TraxeWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [
                                Color(.systemGray6),
                                Color(.systemGray5),
                            ]
                            : [
                                Color(.systemGray5),
                                Color(.systemGray4),
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Hashrate Widget")
        .description("Track your fleet or a single miner.")
        .supportedFamilies(supportedFamilies)
    }
}

#Preview("accessoryCircular", as: .accessoryCircular) {
    TraxeWidget()
} timeline: {
    SimpleEntry(date: .now, hashrate: "", totalDevices: 0, lastUpdated: nil)
    SimpleEntry(
        date: .now,
        hashrate: "832.60",
        totalDevices: 2,
        successfulFetches: 2,
        lastUpdated: .now
    )
    SimpleEntry(
        date: .now,
        hashrate: "1416.30",
        totalDevices: 2,
        successfulFetches: 1,
        lastUpdated: .now.addingTimeInterval(-300)
    )
    SimpleEntry(
        date: .now,
        hashrate: "Error",
        totalDevices: 2,
        successfulFetches: 0,
        lastUpdated: .now.addingTimeInterval(-1800)
    )
    SimpleEntry(date: .now, hashrate: "--", isPlaceholder: true, lastUpdated: nil)
}

#Preview("accessoryInline", as: .accessoryInline) {
    TraxeWidget()
} timeline: {
    SimpleEntry(date: .now, hashrate: "", totalDevices: 0, lastUpdated: nil)
    SimpleEntry(
        date: .now,
        hashrate: "832.60",
        totalDevices: 2,
        successfulFetches: 2,
        lastUpdated: .now
    )
    SimpleEntry(
        date: .now,
        hashrate: "1416.30",
        totalDevices: 2,
        successfulFetches: 1,
        lastUpdated: .now.addingTimeInterval(-300)
    )
    SimpleEntry(
        date: .now,
        hashrate: "Error",
        totalDevices: 2,
        successfulFetches: 0,
        lastUpdated: .now.addingTimeInterval(-1800)
    )
    SimpleEntry(date: .now, hashrate: "--", isPlaceholder: true, lastUpdated: nil)
}

#Preview("accessoryRectangular", as: .accessoryRectangular) {
    TraxeWidget()
} timeline: {
    SimpleEntry(date: .now, hashrate: "", totalDevices: 0, lastUpdated: nil)
    SimpleEntry(
        date: .now,
        hashrate: "832.60",
        totalDevices: 2,
        successfulFetches: 2,
        lastUpdated: .now
    )
    SimpleEntry(
        date: .now,
        hashrate: "1416.30",
        totalDevices: 2,
        successfulFetches: 1,
        lastUpdated: .now.addingTimeInterval(-300)
    )
    SimpleEntry(
        date: .now,
        hashrate: "Error",
        totalDevices: 2,
        successfulFetches: 0,
        lastUpdated: .now.addingTimeInterval(-1800)
    )
    SimpleEntry(date: .now, hashrate: "--", isPlaceholder: true, lastUpdated: nil)
}

#Preview("systemSmall", as: .systemSmall) {
    TraxeWidget()
} timeline: {
    SimpleEntry(date: .now, hashrate: "", totalDevices: 0, lastUpdated: nil)
    SimpleEntry(
        date: .now,
        hashrate: "832.60",
        totalDevices: 2,
        successfulFetches: 2,
        lastUpdated: .now
    )
    SimpleEntry(
        date: .now,
        hashrate: "1416.30",
        totalDevices: 2,
        successfulFetches: 1,
        lastUpdated: .now.addingTimeInterval(-300)
    )
    SimpleEntry(
        date: .now,
        hashrate: "Error",
        totalDevices: 2,
        successfulFetches: 0,
        lastUpdated: .now.addingTimeInterval(-1800)
    )
    SimpleEntry(date: .now, hashrate: "--", isPlaceholder: true, lastUpdated: nil)
}

#Preview("systemSmall groupedHashrate", as: .systemSmall) {
    TraxeWidget()
} timeline: {
    SimpleEntry(
        date: .now,
        hashrate: "10,818.3",
        totalDevices: 6,
        successfulFetches: 6,
        lastUpdated: .now
    )
}

#Preview("systemLarge fleet", as: .systemLarge) {
    TraxeWidget()
} timeline: {
    SimpleEntry(
        date: .now,
        hashrate: "15400.0",
        totalDevices: 7,
        successfulFetches: 6,
        lastUpdated: .now,
        fleetStatus: WidgetFleetStatus(
            total: 7,
            online: 5,
            paused: 0,
            offline: 2,
            unknown: 0
        )
    )
}

#Preview("systemLarge zero hashrate", as: .systemLarge) {
    TraxeWidget()
} timeline: {
    SimpleEntry(
        date: .now,
        hashrate: "10500.0",
        totalDevices: 7,
        successfulFetches: 5,
        lastUpdated: .now,
        metricStatus: "5 of 7 miners reporting",
        fleetStatus: WidgetFleetStatus(
            total: 7,
            online: 5,
            paused: 0,
            offline: 2,
            unknown: 0,
            zeroHashrate: 1
        )
    )
    SimpleEntry(
        date: .now,
        hashrate: "10500.0",
        totalDevices: 7,
        successfulFetches: 5,
        lastUpdated: .now,
        metricStatus: "4 of 7 miners with hash rate",
        fleetStatus: WidgetFleetStatus(
            total: 7,
            online: 3,
            paused: 1,
            offline: 2,
            unknown: 1,
            zeroHashrate: 1
        )
    )
}
