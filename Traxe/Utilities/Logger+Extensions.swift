import Foundation
import os.log

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier!

    /// Logs network-related activities.
    static let networking = Logger(subsystem: subsystem, category: "networking")

    /// Logs settings-related activities.
    static let settings = Logger(subsystem: subsystem, category: "settings")

    /// Logs dashboard-related activities.
    static let dashboard = Logger(subsystem: subsystem, category: "dashboard")

    /// Logs onboarding-related activities.
    static let onboarding = Logger(subsystem: subsystem, category: "onboarding")
}
