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
private struct CachedDeviceMetrics: Codable {
    var hashrate: Double
    var power: Double?
    var bestDifficulty: Double?
    var hostname: String?
    var poolURL: String?
    // Include temperature so widget preserves it in the shared cache
    var temperature: Double?
    var lastUpdated: Date
}

struct Provider: TimelineProvider {
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

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let entry = SimpleEntry(
            date: Date(),
            hashrate: "416.30",
            totalDevices: 1,
            lastUpdated: Date()
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        Task {
            guard let sharedDefaults = UserDefaults(suiteName: appGroupID),
                let ipAddresses = sharedDefaults.array(forKey: savedDevicesKey) as? [String],
                !ipAddresses.isEmpty
            else {
                let entry = SimpleEntry(
                    date: Date(),
                    hashrate: "Setup",
                    totalDevices: 0,
                    lastUpdated: nil
                )
                let timeline = Timeline(
                    entries: [entry],
                    policy: .after(Date().addingTimeInterval(60 * 15))
                )
                completion(timeline)
                return
            }

            let currentDate = Date()
            let refreshDate = Calendar.current.date(byAdding: .minute, value: 10, to: currentDate)!
            let networkService = getNetworkService()
            // Load existing per-device cache (shared with the app)
            let perDeviceCache = loadDeviceMetricsCache()

            // Fetch per-device hashrates in parallel and merge with cache
            var fetchedHashrates: [String: Double] = [:]
            var fetchedTemps: [String: Double] = [:]
            await withTaskGroup(of: (String, (hash: Double?, temp: Double?)).self) { group in
                for ip in ipAddresses {
                    group.addTask {
                        do {
                            let systemInfo = try await networkService.fetchSystemInfo(
                                ipAddressOverride: ip
                            )
                            return (ip, (hash: systemInfo.hashrate, temp: systemInfo.temp))
                        } catch {
                            return (ip, (hash: nil, temp: nil))
                        }
                    }
                }

                for await (ip, fresh) in group {
                    if let hashrate = fresh.hash { fetchedHashrates[ip] = hashrate }
                    if let temp = fresh.temp { fetchedTemps[ip] = temp }
                }
            }

            // Merge: prefer fresh values; fallback to cached per device; prune to current IPs
            var merged: [String: CachedDeviceMetrics] = [:]
            let now = Date()
            for ip in ipAddresses {
                if let fresh = fetchedHashrates[ip] {
                    var entry =
                        perDeviceCache[ip]
                        ?? CachedDeviceMetrics(
                            hashrate: fresh,
                            power: 0.0,  // write non-nil default to keep cache clean
                            bestDifficulty: 0.0,  // write non-nil default to keep cache clean
                            hostname: nil,
                            poolURL: nil,
                            temperature: nil,
                            lastUpdated: now
                        )
                    entry.hashrate = fresh
                    if let t = fetchedTemps[ip] { entry.temperature = t }
                    // If we fetched system info above we had temperature; but since we only stored hash here,
                    // keep existing temperature if present rather than dropping it.
                    // Note: A more robust approach is to plumb temp through fetched map as well.
                    entry.lastUpdated = now
                    merged[ip] = entry
                } else if let cached = perDeviceCache[ip] {
                    merged[ip] = cached
                }
            }

            // Compute total from merged per-device metrics (only current IPs)
            let totalHashrate = merged.values.reduce(0.0) { $0 + $1.hashrate }
            let successfulFetches = fetchedHashrates.count
            let displayHashrate =
                totalHashrate.formatted(.number.precision(.fractionLength(1)))

            // Determine freshness timestamp
            let mostRecentUpdate = merged.values.map(\.lastUpdated).max()
            let freshnessDate: Date
            if successfulFetches > 0 {
                freshnessDate = now  // Some data is fresh this run
            } else {
                freshnessDate = mostRecentUpdate ?? currentDate  // Use oldest real data from cache
            }

            // Save merged per-device cache for app + widget consistency
            saveDeviceMetricsCache(merged)

            // Also keep lastKnownWidgetData for backward compatibility
            if successfulFetches > 0 {
                cacheLastKnownData(
                    hashrate: displayHashrate,
                    totalDevices: ipAddresses.count,
                    successfulFetches: successfulFetches
                )
            }

            let entry = SimpleEntry(
                date: currentDate,
                hashrate: displayHashrate,
                totalDevices: ipAddresses.count,
                successfulFetches: successfulFetches,
                lastUpdated: freshnessDate
            )
            let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
            completion(timeline)
        }
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

        let totalHashrate = metrics.values.reduce(0.0) { $0 + $1.hashrate }
        let lastUpdated = metrics.values.compactMap(\.lastUpdated).max() ?? Date()

        let payload: [String: Any] = [
            "cacheData": data,
            "totalHashrate": totalHashrate,
            "lastUpdated": lastUpdated,
            "deviceCount": metrics.count,
        ]

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
}

struct TraxeWidgetEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily
    @Environment(\.widgetRenderingMode) var renderingMode
    var entry: Provider.Entry

    var body: some View {

        switch widgetFamily {

        case .accessoryCircular:

            VStack(alignment: .leading, spacing: 4) {
                Text("HASH RATE".uppercased())
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

                Text("\(valueText) \(unitText)")
                    .fontDesign(.rounded)
                    .minimumScaleFactor(0.5)

            }

        case .accessoryRectangular:

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    let (valueText, unitText) = Self.formatHashrate(entry.hashrate)
                    HStack {
                        Text("HASH RATE".uppercased())
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
                    Text("HASH RATE".uppercased())
                        .font(.caption2)
                        .foregroundStyle(Color.traxeGold)
                        .fontDesign(.rounded)

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

                    Text("at \(entry.lastUpdated ?? entry.date, style: .time)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fontDesign(.rounded)

                }
                //        .padding(.vertical, 10)
                .padding(.all, 10.0)
                Spacer()
            }

        default:

            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("HASH RATE".uppercased())
                        .font(.caption2)
                        .foregroundStyle(Color.traxeGold)
                        .fontDesign(.rounded)

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

                    Text("at \(entry.lastUpdated ?? entry.date, style: .time)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fontDesign(.rounded)

                }
                //        .padding(.vertical, 10)
                .padding(.all, 10.0)
                Spacer()
            }

        }

    }

    private static func formatHashrate(_ hashrateString: String) -> (value: String, unit: String) {
        if hashrateString == "--" || hashrateString == "Error" {
            return (value: hashrateString, unit: "")
        }

        let isPartial = hashrateString.hasSuffix("+")
        let numericString = isPartial ? String(hashrateString.dropLast()) : hashrateString

        guard let value = Double(numericString) else {
            return (value: hashrateString, unit: "")
        }

        let partialSuffix = isPartial ? "" : ""

        if value >= 1000 {
            let teraValue = value / 1000
            return (
                value: teraValue.formatted(.number.precision(.fractionLength(1))) + partialSuffix,
                unit: "TH/s"
            )
        } else {
            return (
                value: value.formatted(.number.precision(.fractionLength(1))) + partialSuffix,
                unit: "GH/s"
            )
        }
    }
}

struct TraxeWidget: Widget {
    let kind: String = "TraxeWidget"
    @Environment(\.colorScheme) var colorScheme

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                TraxeWidgetEntryView(entry: entry)
                    .containerBackground(for: .widget) {
                        //                        ZStack {
                        //                            // Base layer - solid background
                        //                            RoundedRectangle(cornerRadius: 20)
                        //                                .fill(
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
                        //                                )
                        //                                .shadow(color: .black.opac/*ity(0.1), radius: 8, x: 0, y: 4)*/

                        // Simple glass layer on top
                        //                            RoundedRectangle(cornerRadius: 20)
                        //                                .fill(.ultraThinMaterial)
                        //                                .overlay(
                        //                                    RoundedRectangle(cornerRadius: 20)
                        //                                        .stroke(.white.opacity(0.3), lineWidth: 1)
                        //                                )
                        //                        }
                    }
            } else {
                TraxeWidgetEntryView(entry: entry)
                    .padding()
                    .background(
                        ZStack {
                            // Base layer - solid background
                            RoundedRectangle(cornerRadius: 20)
                                .fill(
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
                                )
                                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)

                            // Simple glass layer on top
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(.white.opacity(0.3), lineWidth: 1)
                                )
                        }
                    )
            }
        }
        .configurationDisplayName("Hashrate Widget")
        .description("This is a hashrate widget.")
        .supportedFamilies([
            .accessoryCircular, .accessoryInline, .accessoryRectangular, .systemSmall,
        ])
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
