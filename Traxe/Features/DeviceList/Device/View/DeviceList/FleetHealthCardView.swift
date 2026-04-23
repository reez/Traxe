import SwiftUI

struct FleetHealthCardView: View {
    let snapshot: FleetHealthSnapshot
    let isLoading: Bool

    private var stateSegments: [FleetHealthSignalSegment] {
        [
            FleetHealthSignalSegment(
                id: "online",
                title: "Online",
                count: snapshot.online,
                color: .traxeGold
            ),
            FleetHealthSignalSegment(
                id: "paused",
                title: "Paused",
                count: snapshot.paused,
                color: .traxeGold.opacity(0.25)
            ),
            FleetHealthSignalSegment(
                id: "offline",
                title: "Offline",
                count: snapshot.offline,
                color: Color(uiColor: .tertiaryLabel)
            ),
            FleetHealthSignalSegment(
                id: "unknown",
                title: "Unknown",
                count: snapshot.unknown,
                color: .secondary
            ),
        ]
    }

    private var alertSegments: [FleetHealthSignalSegment] {
        [
            FleetHealthSignalSegment(
                id: "zero-hashrate",
                title: "Hashrate = 0",
                count: snapshot.zeroHashrate,
                color: .secondary
            ),
            FleetHealthSignalSegment(
                id: "high-temperature",
                title: "Temp 75°C+",
                count: snapshot.highTemperature,
                color: .red
            ),
        ]
    }

    private var alertSignalTotal: Int {
        alertSegments.reduce(0) { $0 + $1.count }
    }

    private var accessibilityLabelText: String {
        if isLoading {
            return "Fleet Health. Loading miner status."
        }

        var parts = ["Fleet Health."]
        let statusSignals = [
            accessibilitySignal(count: snapshot.online, label: "online"),
            accessibilitySignal(count: snapshot.paused, label: "paused"),
            accessibilitySignal(count: snapshot.offline, label: "offline"),
            accessibilitySignal(count: snapshot.unknown, label: "unknown"),
        ].compactMap(\.self)
        let alertSignals = [
            accessibilitySignal(count: snapshot.zeroHashrate, label: "hashrate equals zero"),
            accessibilitySignal(
                count: snapshot.highTemperature,
                label: "temperature 75 degrees Celsius or higher"
            ),
        ].compactMap(\.self)

        if statusSignals.isEmpty {
            parts.append("No miners.")
        } else {
            parts.append("\(statusSignals.joined(separator: ", ")).")
        }

        if !alertSignals.isEmpty {
            parts.append("Alerts: \(alertSignals.joined(separator: ", ")).")
        }

        return parts.joined(separator: " ")
    }

    private func accessibilitySignal(count: Int, label: String) -> String? {
        guard count > 0 else { return nil }
        return "\(count) \(label)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isLoading {
                FleetHealthLoadingGroupView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    FleetHealthSignalGroupView(
                        title: "Status",
                        segments: stateSegments,
                        barTotal: snapshot.totalMiners
                    )
                    FleetHealthSignalGroupView(
                        title: "Alerts",
                        segments: alertSegments,
                        barTotal: alertSignalTotal
                    )
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isLoading)
        .animation(.easeInOut(duration: 0.3), value: snapshot)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
    }
}

#Preview("Fleet Health - All Online") {
    FleetHealthCardView(snapshot: fleetHealthPreviewSnapshot(online: 3), isLoading: false)
        .padding()
}

#Preview("Fleet Health - Paused") {
    FleetHealthCardView(snapshot: fleetHealthPreviewSnapshot(paused: 1), isLoading: false)
        .padding()
}

#Preview("Fleet Health - Offline") {
    FleetHealthCardView(snapshot: fleetHealthPreviewSnapshot(offline: 1), isLoading: false)
        .padding()
}

#Preview("Fleet Health - Unknown") {
    FleetHealthCardView(snapshot: fleetHealthPreviewSnapshot(unknown: 1), isLoading: false)
        .padding()
}

#Preview("Fleet Health - Mixed Status") {
    FleetHealthCardView(
        snapshot: fleetHealthPreviewSnapshot(online: 3, paused: 1, offline: 1, unknown: 1),
        isLoading: false
    )
    .padding()
}

#Preview("Fleet Health - Five Online Two Offline") {
    FleetHealthCardView(
        snapshot: fleetHealthPreviewSnapshot(online: 5, offline: 2),
        isLoading: false
    )
    .padding()
}

#Preview("Fleet Health - Four Online Three Offline") {
    FleetHealthCardView(
        snapshot: fleetHealthPreviewSnapshot(online: 4, offline: 3),
        isLoading: false
    )
    .padding()
}

#Preview("Fleet Health - Hashrate Alert") {
    FleetHealthCardView(
        snapshot: fleetHealthPreviewSnapshot(online: 2, zeroHashrate: 1),
        isLoading: false
    )
    .padding()
}

#Preview("Fleet Health - Temperature Alert") {
    FleetHealthCardView(
        snapshot: fleetHealthPreviewSnapshot(online: 2, highTemperature: 1),
        isLoading: false
    )
    .padding()
}

#Preview("Fleet Health - Multiple Alerts") {
    FleetHealthCardView(
        snapshot: fleetHealthPreviewSnapshot(
            online: 3,
            paused: 1,
            offline: 1,
            unknown: 1,
            zeroHashrate: 1,
            highTemperature: 1
        ),
        isLoading: false
    )
    .padding()
}

#Preview("Fleet Health - Loading") {
    FleetHealthCardView(snapshot: fleetHealthPreviewSnapshot(offline: 7), isLoading: true)
        .padding()
}

#Preview("Fleet Health - Loading Narrow") {
    FleetHealthCardView(snapshot: fleetHealthPreviewSnapshot(offline: 7), isLoading: true)
        .padding()
        .frame(width: 280)
}

private func fleetHealthPreviewSnapshot(
    online: Int = 0,
    paused: Int = 0,
    offline: Int = 0,
    unknown: Int = 0,
    zeroHashrate: Int = 0,
    highTemperature: Int = 0
) -> FleetHealthSnapshot {
    FleetHealthSnapshot(
        totalMiners: online + paused + offline + unknown,
        online: online,
        paused: paused,
        offline: offline,
        unknown: unknown,
        zeroHashrate: zeroHashrate,
        highTemperature: highTemperature
    )
}
