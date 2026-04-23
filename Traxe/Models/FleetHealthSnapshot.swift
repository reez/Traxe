import Foundation

struct FleetHealthSnapshot: Equatable {
    var totalMiners: Int
    var online: Int
    var paused: Int
    var offline: Int
    var unknown: Int
    var zeroHashrate: Int
    var highTemperature: Int

    var stateSummaryText: String {
        guard totalMiners > 0 else { return "No miners" }
        let summaries = [
            "\(online)/\(totalMiners) online",
            signalSummary(count: paused, label: "paused"),
            signalSummary(count: offline, label: "offline"),
            signalSummary(count: unknown, label: "unknown"),
        ].compactMap(\.self)

        return summaries.joined(separator: ", ")
    }

    var alertSummaryText: String {
        let summaries = [
            signalSummary(count: zeroHashrate, label: "hashrate = 0"),
            signalSummary(count: highTemperature, label: "temp 75°C+"),
        ].compactMap(\.self)

        guard !summaries.isEmpty else { return "No alerts" }
        return summaries.joined(separator: ", ")
    }

    private func signalSummary(count: Int, label: String) -> String? {
        guard count > 0 else { return nil }
        return "\(count) \(label)"
    }

    static func make(
        devices: [SavedDevice],
        metricsByIP: [String: DeviceMetrics],
        reachableIPs: Set<String>,
        isRefreshing: Bool,
        hotTemperatureThreshold: Double = AppConstants.AI.hotTemperatureThreshold
    ) -> Self {
        var snapshot = FleetHealthSnapshot(
            totalMiners: devices.count,
            online: 0,
            paused: 0,
            offline: 0,
            unknown: 0,
            zeroHashrate: 0,
            highTemperature: 0
        )

        for device in devices {
            let metrics = metricsByIP[device.ipAddress]
            let isReachable = reachableIPs.contains(device.ipAddress)

            guard isReachable else {
                snapshot.offline += 1
                continue
            }

            guard let metrics else {
                snapshot.unknown += 1
                continue
            }

            if metrics.isMiningPausedKnown && metrics.isMiningPaused {
                snapshot.paused += 1
            } else {
                snapshot.online += 1
            }

            if metrics.isHashrateKnown && metrics.hashrate == 0 {
                snapshot.zeroHashrate += 1
            }

            if metrics.isTemperatureKnown && metrics.temperature >= hotTemperatureThreshold {
                snapshot.highTemperature += 1
            }
        }

        return snapshot
    }
}
