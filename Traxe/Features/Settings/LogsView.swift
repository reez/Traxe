import OSLog
import SwiftUI

// 1. Simple struct to hold log data and make it Identifiable for the List
struct LogEntry: Identifiable {
    let id = UUID()
    let level: OSLogEntryLog.Level
    let date: Date
    let category: String
    let message: String

    var formatted: String {
        "[\(level.toString())] [\(date.formatted())] [\(category)] \(message)"
    }
}

struct LogsView: View {
    @Environment(\.dismiss) var dismiss
    // 2. Change state to hold an array of LogEntry
    @State private var logEntries: [LogEntry] = []
    @State private var isLoading: Bool = true  // Add loading state

    var body: some View {
        NavigationView {
            // 4. Use a List iterating over logEntries
            List {
                if isLoading {
                    ProgressView("Loading logs...")
                } else if logEntries.isEmpty {
                    Text("No logs found for the last 24 hours.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(logEntries) { entry in
                        Text(entry.formatted)
                            .font(.system(.caption2, design: .monospaced))
                            .listRowInsets(EdgeInsets(top: 2, leading: 5, bottom: 2, trailing: 5))  // Reduce padding
                    }
                }
            }
            .listStyle(.plain)  // Use plain style for less visual clutter
            .navigationTitle("App Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                // Group the trailing items
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Trash Button
                    Button {
                        clearDisplayedLogs()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(logEntries.isEmpty)  // Disable if no logs to clear

                    // Share Button
                    Button {
                        shareLogs()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(logEntries.isEmpty)  // Disable share if no logs
                }
            }
            .onAppear {
                fetchLogs()
            }
        }
    }

    // 3. Update fetchLogs to populate the array
    private func fetchLogs() {
        isLoading = true  // Start loading
        Logger.ui.debug("Starting fetchLogs...")
        Task {
            var fetchedEntries: [LogEntry] = []
            var errorMessage: String?

            do {
                Logger.ui.debug("Attempting to initialize OSLogStore.")
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                Logger.ui.debug("OSLogStore initialized.")

                let twentyFourHoursAgo = Date().addingTimeInterval(-86400)
                let position = store.position(date: twentyFourHoursAgo)
                Logger.ui.debug("Fetching entries since \(twentyFourHoursAgo.formatted()).")

                let subsystem = Bundle.main.bundleIdentifier!
                let predicate = NSPredicate(format: "subsystem == %@", subsystem)
                let entries = try store.getEntries(with: [], at: position, matching: predicate)
                let reversedEntries = entries.reversed()

                Logger.ui.debug(
                    "Found \(reversedEntries.count) log entries for subsystem '\(subsystem)'."
                )

                let limitedEntries = reversedEntries.prefix(200)  // Still limit fetched/processed count
                Logger.ui.debug(
                    "Processing the latest \(limitedEntries.count) entries for display."
                )

                // Map to LogEntry structs
                fetchedEntries =
                    limitedEntries
                    .compactMap { $0 as? OSLogEntryLog }
                    .map { entry in
                        LogEntry(
                            level: entry.level,
                            date: entry.date,
                            category: entry.category,
                            message: entry.composedMessage
                        )
                    }

                Logger.ui.debug("Successfully processed log entries.")

            } catch {
                errorMessage = "Error fetching logs: \(error.localizedDescription)"
                Logger.ui.error("Error fetching logs: \(error.localizedDescription)")
            }

            // Update state on the main thread
            await MainActor.run {
                self.logEntries = fetchedEntries
                if let msg = errorMessage {
                    // Handle error display if needed, maybe show an alert or placeholder text
                    // For now, just log it, `logEntries` will be empty triggering the "No logs" text
                }
                self.isLoading = false  // Finish loading
            }
        }
    }

    // Add this new function inside LogsView:
    private func clearDisplayedLogs() {
        // Clear the array holding the displayed logs
        logEntries.removeAll()
        // Optionally add user feedback, e.g., a temporary message or just rely on the empty state text
        Logger.ui.info("Cleared displayed logs in LogsView.")
        // NOTE: This does NOT delete logs from the device's OSLogStore.
    }

    // 5. Update shareLogs to format the array
    private func shareLogs() {
        guard !logEntries.isEmpty else { return }
        let logText = logEntries.map { $0.formatted }.joined(separator: "\n")

        let activityController = UIActivityViewController(
            activityItems: [logText],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let rootViewController = windowScene.windows.first?.rootViewController
        {
            var topController = rootViewController
            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
            }
            topController.present(activityController, animated: true, completion: nil)
            Logger.ui.info("Sharing logs initiated.")
        } else {
            Logger.ui.error("Could not find root view controller to present share sheet.")
        }
    }
}

// Helper extension for OSLogEntryLog.Level if using OSLogStore
extension OSLogEntryLog.Level {
    func toString() -> String {
        switch self {
        case .undefined: return "UNDEFINED"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        @unknown default: return "UNKNOWN"
        }
    }
}

// Modify the Logger extension slightly for clarity and potential safety
extension Logger {
    // Use a lazy var for subsystem to ensure it's initialized only when first needed.
    private static let subsystem: String = {
        guard let identifier = Bundle.main.bundleIdentifier else {
            // Fallback or assertion if bundle ID is unexpectedly nil
            assertionFailure("Bundle identifier is nil!")
            return "com.unknown.app"
        }
        return identifier
    }()

    static let ui = Logger(subsystem: subsystem, category: "UI")
    // Add other categories as needed
}

#Preview {
    LogsView()
}
