import SwiftUI
import WidgetKit

// Minimal copy of the widget cache model so the watch extension can read the shared data.
private struct CachedDeviceMetrics: Codable {
    var hashrate: Double
    var power: Double?
    var bestDifficulty: Double?
    var hostname: String?
    var poolURL: String?
    var temperature: Double?
    var lastUpdated: Date
}

struct WatchHashrateProvider: TimelineProvider {
    private let appGroupID = "group.matthewramsden.traxe"
    private let deviceCacheKey = "cachedDeviceMetricsV2"
    private let cachedDataKey = "lastKnownWidgetData"
    private let fallbackRefresh = TimeInterval(60 * 15)

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

    func placeholder(in context: Context) -> WatchHashrateEntry {
        WatchHashrateEntry(date: Date(), hashrate: "--", lastUpdated: nil, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchHashrateEntry) -> Void) {
        let cache = loadDeviceMetricsCache()
        let snapshot = entry(from: cache, referenceDate: Date())
        completion(snapshot ?? placeholder(in: context))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<WatchHashrateEntry>) -> Void
    ) {
        let now = Date()
        let cache = loadDeviceMetricsCache()

        guard let entry = entry(from: cache, referenceDate: now) else {
            let placeholderEntry = WatchHashrateEntry(
                date: now,
                hashrate: "Setup",
                lastUpdated: nil,
                isPlaceholder: false
            )
            let refresh = Date(timeIntervalSinceNow: fallbackRefresh)
            completion(Timeline(entries: [placeholderEntry], policy: .after(refresh)))
            return
        }

        let refreshDate =
            entry.lastUpdated?.addingTimeInterval(60 * 10)
            ?? Date(timeIntervalSinceNow: fallbackRefresh)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func entry(from cache: [String: CachedDeviceMetrics], referenceDate: Date)
        -> WatchHashrateEntry?
    {
        if !cache.isEmpty {
            let totalHashrate = cache.values.reduce(0.0) { $0 + $1.hashrate }
            let displayHashrate = totalHashrate.formattedHashRateWithUnit()
            let freshness = cache.values.compactMap(\.lastUpdated).max()
            return WatchHashrateEntry(
                date: referenceDate,
                hashrate: displayHashrate.value,
                unit: displayHashrate.unit,
                lastUpdated: freshness,
                isPlaceholder: false
            )
        }

        if let legacy = loadLegacyHashrate() {
            return WatchHashrateEntry(
                date: referenceDate,
                hashrate: legacy.value,
                unit: legacy.unit,
                lastUpdated: legacy.lastUpdated,
                isPlaceholder: false
            )
        }

        return nil
    }

    private func loadLegacyHashrate() -> (value: String, unit: String, lastUpdated: Date?)? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
            let cachedData = defaults.dictionary(forKey: cachedDataKey),
            let hashrateString = cachedData["hashrate"] as? String
        else {
            return nil
        }
        let cachedDate = cachedData["cachedDate"] as? Date
        if let rawValue = Double(hashrateString) {
            let formatted = rawValue.formattedHashRateWithUnit()
            return (formatted.value, formatted.unit, cachedDate)
        } else {
            return (hashrateString, "", cachedDate)
        }
    }
}

struct WatchHashrateEntry: TimelineEntry {
    let date: Date
    let hashrate: String
    var unit: String = ""
    let lastUpdated: Date?
    var isPlaceholder: Bool
}

struct TraxeWatchWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WatchHashrateProvider.Entry

    var body: some View {
        switch family {
        case .accessoryRectangular:

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOTAL HASH RATE")
                        .font(.caption2)
                        .fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.25)

                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(entry.hashrate)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .fontDesign(.rounded)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .redacted(reason: entry.isPlaceholder ? .placeholder : [])

                        if !entry.unit.isEmpty {
                            Text(entry.unit)
                                .font(.caption2)
                                .fontDesign(.rounded)
                                .foregroundStyle(.secondary)
                                .minimumScaleFactor(0.25)
                        }
                    }

                    //                    if let lastUpdated = entry.lastUpdated {
                    //                        Text(lastUpdated, style: .time)
                    //                            .font(.caption2)
                    //                            .foregroundStyle(.tertiary)
                    //                            .fontDesign(.rounded)
                    //                    }
                }
                Spacer()
            }
        case .accessoryInline:

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(entry.hashrate)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .fontDesign(.rounded)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .redacted(reason: entry.isPlaceholder ? .placeholder : [])

                if !entry.unit.isEmpty {
                    Text(entry.unit)
                        .font(.caption2)
                        .fontDesign(.rounded)
                        .minimumScaleFactor(0.25)
                        .foregroundStyle(.secondary)
                }
            }

        case .accessoryCorner:

            VStack(spacing: 4) {
                Text(entry.hashrate)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .fontDesign(.rounded)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .redacted(reason: entry.isPlaceholder ? .placeholder : [])

                if !entry.unit.isEmpty {
                    Text(entry.unit)
                        .font(.caption2)
                        .fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.25)
                }
            }

        case .accessoryCircular:

            VStack(spacing: 4) {
                Text(entry.hashrate)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .fontDesign(.rounded)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .redacted(reason: entry.isPlaceholder ? .placeholder : [])

                if !entry.unit.isEmpty {
                    Text(entry.unit)
                        .font(.caption2)
                        .fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.25)

                }
            }

        default:
            VStack(alignment: .leading, spacing: 6) {
                Text("Hashrate")
                    .font(.headline)
                    .fontDesign(.rounded)
                Text(entry.hashrate)
                    .font(.title)
                    .fontWeight(.bold)
                    .fontDesign(.rounded)
                    .minimumScaleFactor(0.6)
                    .redacted(reason: entry.isPlaceholder ? .placeholder : [])
                if !entry.unit.isEmpty {
                    Text(entry.unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontDesign(.rounded)
                }
            }
        }
    }
}

struct TraxeWatchWidget: Widget {
    let kind: String = "TraxeWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchHashrateProvider()) { entry in
            if #available(watchOS 10.0, *) {
                TraxeWatchWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                TraxeWatchWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("Hashrate")
        .description("Latest hashrate from your miners.")
    }
}

#Preview("accessoryRectangular", as: .accessoryRectangular) {
    TraxeWatchWidget()
} timeline: {
    WatchHashrateEntry(
        date: Date.now,
        hashrate: "432.1",
        unit: "GH/s",
        lastUpdated: Date.now,
        isPlaceholder: false
    )
}

#Preview("accessoryInline", as: .accessoryInline) {
    TraxeWatchWidget()
} timeline: {
    WatchHashrateEntry(
        date: Date.now,
        hashrate: "432.1",
        unit: "GH/s",
        lastUpdated: Date.now,
        isPlaceholder: false
    )
}

#if os(watchOS)
    #Preview("accessoryCorner", as: .accessoryCorner) {
        TraxeWatchWidget()
    } timeline: {
        WatchHashrateEntry(
            date: Date.now,
            hashrate: "432.1",
            unit: "GH/s",
            lastUpdated: Date.now,
            isPlaceholder: false
        )
    }
#endif

#Preview("accessoryCircular", as: .accessoryCircular) {
    TraxeWatchWidget()
} timeline: {
    WatchHashrateEntry(
        date: Date.now,
        hashrate: "432.1",
        unit: "GH/s",
        lastUpdated: Date.now,
        isPlaceholder: false
    )
}
