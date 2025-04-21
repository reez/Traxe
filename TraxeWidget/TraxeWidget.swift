//
//  TraxeWidget.swift
//  TraxeWidget
//
//  Created by Matthew Ramsden on 4/20/25.
//

import SwiftUI
import WidgetKit

struct Provider: TimelineProvider {
    // Define the App Group ID - MAKE SURE THIS MATCHES THE ONE YOU SET UP!
    let appGroupID = "group.matthewramsden.traxe"

    // Helper to get NetworkService instance with shared defaults
    private func getNetworkService() -> NetworkService? {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupID),
            sharedDefaults.string(forKey: "bitaxeIPAddress") != nil  // Check if IP exists
        else {
            return nil  // Cannot proceed without IP
        }
        // You might want to configure the session specifically for the widget
        // e.g., shorter timeouts if needed.
        return NetworkService()  // Assumes NetworkService init can access the shared defaults implicitly now
    }

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), hashrate: "--")  // Use a placeholder for loading/error
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        // Provide a quick snapshot. For previews or brief looks.
        // You could do a quick fetch here if desired, but often a recent known value or placeholder is fine.
        let entry = SimpleEntry(date: Date(), hashrate: "416.30")  // Example static snapshot
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        Task {
            guard let networkService = getNetworkService() else {
                // If network service setup fails (e.g., no IP), provide an error entry
                let entry = SimpleEntry(date: Date(), hashrate: "Setup?")
                let timeline = Timeline(
                    entries: [entry],
                    policy: .after(Date().addingTimeInterval(60 * 5))
                )  // Retry after 5 mins
                completion(timeline)
                return
            }

            let currentDate = Date()
            let refreshDate = Calendar.current.date(byAdding: .minute, value: 5, to: currentDate)!

            var fetchedHashrate: String = "--"  // Default/error state

            do {
                // Assuming fetchSystemInfo returns SystemInfoDTO with hashrate info
                let systemInfo = try await networkService.fetchSystemInfo()

                // *** ADJUST THIS PART based on your SystemInfoDTO structure ***
                // hashRate is a non-optional Double, so no need for 'if let'
                fetchedHashrate = String(format: "%.2f", systemInfo.hashRate)  // Format to 2 decimal places

                // Example 2: If hashrate is already a String
                // fetchedHashrate = systemInfo.hashrateString ?? "N/A" // Replace 'hashrateString'

            } catch let error as NetworkError {
                // Check if the error is due to missing configuration
                if case .configurationMissing = error {
                    fetchedHashrate = "Setup?"  // Show setup message
                } else {
                    fetchedHashrate = "Error"  // Or more specific based on error type
                }
            } catch {
                fetchedHashrate = "Error"
            }

            let entry = SimpleEntry(date: currentDate, hashrate: fetchedHashrate)

            // Schedule the next update. Check Apple's docs for recommendations.
            // Requesting update after 5 minutes.
            let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
            completion(timeline)
        }
    }

    //    func relevances() async -> WidgetRelevances<Void> {
    //        // Generate a list containing the contexts this widget is relevant in.
    //    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let hashrate: String  // Keep as String for flexibility (errors, formatting)
}

struct TraxeWidgetEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily
    @Environment(\.widgetRenderingMode) var renderingMode
    var entry: Provider.Entry

    var body: some View {

        VStack(alignment: .leading, spacing: 5) {

            HStack {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                Text("Hash Rate")
                    .fontWeight(.semibold)
            }
            .font(.caption)

            Spacer()

            HStack(alignment: .firstTextBaseline) {
                let isNumericHashrate = Double(entry.hashrate) != nil

                Text(entry.hashrate)
                    .font(.title)
                    .fontWeight(.medium)
                    .minimumScaleFactor(0.5)  // Allow text to shrink if needed
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .redacted(reason: isNumericHashrate ? [] : .placeholder)  // Redact if not a valid number

                // Only show GH/s if the hashrate is a valid number
                if isNumericHashrate {
                    Text("GH/s")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

        }

        // Add timestamp at the bottom
        Spacer()
        Text("Updated: \(entry.date, style: .time)")
            .font(.caption2)
            .foregroundStyle(.secondary)

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
        //        .widgetAccentable()
        .disfavoredLocations([.homeScreen, .lockScreen, .iPhoneWidgetsOnMac], for: [.systemSmall])  // Disallow on Lock Screen for small family
    }
}

#Preview(as: .systemSmall) {
    TraxeWidget()
} timeline: {
    SimpleEntry(date: .now, hashrate: "416.30")
    SimpleEntry(date: .now, hashrate: "--")
    SimpleEntry(date: .now, hashrate: "Error")
}
