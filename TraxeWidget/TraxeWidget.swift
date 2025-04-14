import SwiftUI
import WidgetKit

struct Provider: TimelineProvider {
    let appGroupID = "group.matthewramsden.traxe"
    let savedDevicesKey = "savedDeviceIPs"

    private func getNetworkService() -> NetworkService {
        return NetworkService()
    }

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), hashrate: "--", isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let entry = SimpleEntry(date: Date(), hashrate: "416.30", totalDevices: 1)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        Task {
            guard let sharedDefaults = UserDefaults(suiteName: appGroupID),
                let ipAddresses = sharedDefaults.array(forKey: savedDevicesKey) as? [String],
                !ipAddresses.isEmpty
            else {
                let entry = SimpleEntry(date: Date(), hashrate: "Setup", totalDevices: 0)
                let timeline = Timeline(
                    entries: [entry],
                    policy: .after(Date().addingTimeInterval(60 * 15))
                )
                completion(timeline)
                return
            }

            let currentDate = Date()
            let refreshDate = Calendar.current.date(byAdding: .minute, value: 5, to: currentDate)!
            let networkService = getNetworkService()
            var totalHashrate: Double = 0.0
            var successfulFetches = 0

            await withTaskGroup(of: Double?.self) { group in
                for ip in ipAddresses {
                    group.addTask {
                        do {
                            let systemInfo = try await networkService.fetchSystemInfo(
                                ipAddressOverride: ip
                            )
                            return systemInfo.hashRate
                        } catch {
                            return nil
                        }
                    }
                }

                for await hashrateResult in group {
                    if let hashrate = hashrateResult {
                        totalHashrate += hashrate
                        successfulFetches += 1
                    }
                }
            }

            let displayHashrate: String
            if successfulFetches == 0 && !ipAddresses.isEmpty {
                displayHashrate = "Error"
            } else if successfulFetches < ipAddresses.count {
                displayHashrate = String(format: "%.2f", totalHashrate)
            } else {
                displayHashrate = String(format: "%.2f", totalHashrate)
            }

            let entry = SimpleEntry(
                date: currentDate,
                hashrate: displayHashrate,
                totalDevices: ipAddresses.count,
                successfulFetches: successfulFetches
            )
            let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
            completion(timeline)
        }
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let hashrate: String
    var totalDevices: Int = 0
    var successfulFetches: Int = 0
    var isPlaceholder: Bool = false
}

struct TraxeWidgetEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily
    @Environment(\.widgetRenderingMode) var renderingMode
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Total".uppercased())
                .font(.caption2)
            //                .fontWeight(.semibold)
            //                .padding(.bottom, 12)

            HStack(alignment: .firstTextBaseline) {
                Text("HASH RATE".uppercased())
                    .font(.caption2)
                //                    .fontWeight(.semibold)

                let (valueText, unitText) = Self.formatHashrate(entry.hashrate)

                Text(unitText)
                    .font(.caption2)
                //                    .fontWeight(.medium)
                //                    .foregroundStyle(.secondary)
                //                    .padding(.leading, -2)
            }
            .padding(.bottom, 2)
            .foregroundStyle(.secondary)

            //            HStack(alignment: .firstTextBaseline) {
            let (valueText, unitText) = Self.formatHashrate(entry.hashrate)

            Text(valueText)
                .font(.title)
                .fontWeight(.bold)
                .fontDesign(.rounded)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())
                .redacted(reason: entry.isPlaceholder ? .placeholder : [])

            //                Text(unitText)
            //                    .font(.caption)
            //                    .fontWeight(.medium)
            //                    .foregroundStyle(.secondary)
            //                    .padding(.leading, -2)
            //            }

            Spacer()

            Text("Updated: \(entry.date, style: .time)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
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
            return (value: String(format: "%.2f", teraValue) + partialSuffix, unit: "TH/s")
        } else {
            return (value: String(format: "%.2f", value) + partialSuffix, unit: "GH/s")
        }
    }
}

struct TraxeWidget: Widget {
    let kind: String = "TraxeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                TraxeWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                TraxeWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("Hashrate Widget")
        .description("This is a hashrate widget.")
        .supportedFamilies([.systemSmall])
        .disfavoredLocations([.homeScreen, .lockScreen, .iPhoneWidgetsOnMac], for: [.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    TraxeWidget()
} timeline: {
    SimpleEntry(date: .now, hashrate: "", totalDevices: 0)
    SimpleEntry(date: .now, hashrate: "832.60", totalDevices: 2, successfulFetches: 2)
    SimpleEntry(date: .now, hashrate: "1416.30", totalDevices: 2, successfulFetches: 1)
    SimpleEntry(date: .now, hashrate: "Error", totalDevices: 2, successfulFetches: 0)
    SimpleEntry(date: .now, hashrate: "--", isPlaceholder: true)
}
