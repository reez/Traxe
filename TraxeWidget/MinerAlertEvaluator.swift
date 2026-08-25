import Foundation
import UserNotifications

/// Decides whether a widget timeline refresh warrants a local notification.
///
/// ESP-Miner firmware is a passive HTTP server — there is no push channel, so
/// "offline" can only mean "unreachable from this phone." To keep that signal
/// honest the evaluator:
/// - only runs when the phone has an IPv4 address on the same /24 as the miner
///   (leaving home must not read as an outage),
/// - requires two consecutive failed refreshes before alerting,
/// - alerts once per transition with a cooldown, not once per refresh.
///
/// Alerts are opted into per miner in Settings, and notifications also require the
/// app-global iOS authorization, so both gates are applied before the state machine runs.
///
/// State lives in the app group so it survives across extension process spawns.
enum MinerAlertEvaluator {
    private static let appGroupID = "group.matthewramsden.traxe"
    private static let stateKey = "minerAlertStateV1"

    /// Called from the widget timeline after a refresh's fetches complete.
    /// `respondedIPAddresses` tracks responses independently from optional metrics.
    static func evaluate(
        ipAddresses: [String],
        respondedIPAddresses: Set<String>,
        baselineReachableIPAddresses: Set<String>,
        fetchedTemps: [String: Double],
        hostnames: [String: String],
        referenceDate: Date = Date()
    ) async {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }

        let preferences = MinerAlertPreferences(defaults: defaults)
        preferences.migrateLegacyGlobalPreferenceIfNeeded()

        let center = UNUserNotificationCenter.current()
        let enabledIPAddresses = preferences.enabledIPAddresses
        var alertEnabledIPAddresses: Set<String> = []
        if !enabledIPAddresses.isEmpty {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .authorized {
                alertEnabledIPAddresses = enabledIPAddresses
            }
        }

        let evaluation = MinerAlertStateMachine.evaluate(
            ipAddresses: ipAddresses,
            respondedIPAddresses: respondedIPAddresses,
            baselineReachableIPAddresses: baselineReachableIPAddresses,
            fetchedTemperatures: fetchedTemps,
            hostnames: hostnames,
            localIPv4Prefixes: Set(localIPv4Prefixes()),
            alertEnabledIPAddresses: alertEnabledIPAddresses,
            referenceDate: referenceDate,
            initialState: loadState(from: defaults)
        )
        saveState(evaluation.state, to: defaults)

        for event in evaluation.events {
            switch event {
            case .offline(let ipAddress, let name):
                await schedule(
                    center: center,
                    identifier: "offline-\(ipAddress)",
                    title: "\(name) is offline",
                    body: "No response from \(ipAddress). It may have lost power or network."
                )
            case .hot(let ipAddress, let name, let temperature):
                await schedule(
                    center: center,
                    identifier: "hot-\(ipAddress)",
                    title: "\(name) is running hot",
                    body: "Temperature is \(Int(temperature))°C. Check ventilation."
                )
            }
        }
    }

    // MARK: - Notification scheduling

    private static func schedule(
        center: UNUserNotificationCenter,
        identifier: String,
        title: String,
        body: String
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    // MARK: - Subnet guard

    /// "192.168.1.42" or "192.168.1.42:8081" → "192.168.1."
    private static func slash24Prefix(of address: String) -> String? {
        let host = address.split(separator: ":").first.map(String.init) ?? address
        let octets = host.split(separator: ".")
        guard octets.count == 4 else { return nil }
        return octets.prefix(3).joined(separator: ".") + "."
    }

    private static func localIPv4Prefixes() -> [String] {
        var prefixes: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let interface = ptr?.pointee {
            defer { ptr = interface.ifa_next }
            guard let addr = interface.ifa_addr,
                addr.pointee.sa_family == UInt8(AF_INET),
                let nameBytes = interface.ifa_name,
                ["en0", "en1"].contains(String(cString: nameBytes))
            else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                addr, socklen_t(addr.pointee.sa_len),
                &hostname, socklen_t(hostname.count),
                nil, 0, NI_NUMERICHOST
            ) == 0, let address = String(cString: hostname, encoding: .utf8),
                let prefix = slash24Prefix(of: address)
            {
                prefixes.append(prefix)
            }
        }
        return prefixes
    }

    // MARK: - Persistence

    private static func loadState(from defaults: UserDefaults) -> [String: MinerAlertDeviceState] {
        guard let data = defaults.data(forKey: stateKey),
            let decoded = try? JSONDecoder().decode([String: MinerAlertDeviceState].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func saveState(
        _ state: [String: MinerAlertDeviceState],
        to defaults: UserDefaults
    ) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: stateKey)
        }
    }
}
