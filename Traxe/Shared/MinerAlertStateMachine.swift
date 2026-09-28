import Foundation

struct MinerAlertDeviceState: Codable, Equatable {
    var consecutiveFailures: Int = 0
    var wasReachable: Bool = false
    var lastOfflineAlert: Date? = nil
    var lastHotAlert: Date? = nil
    var wasHot: Bool? = nil
}

enum MinerAlertEvent: Equatable {
    case offline(ipAddress: String, name: String)
    case hot(ipAddress: String, name: String, temperature: Double)
}

struct MinerAlertEvaluation: Equatable {
    let state: [String: MinerAlertDeviceState]
    let events: [MinerAlertEvent]
}

enum MinerAlertStateMachine {
    private static let failuresBeforeOffline = 2
    private static let alertCooldown: TimeInterval = 6 * 60 * 60
    private static let hotTemperatureThreshold = 75.0

    static func evaluate(
        ipAddresses: [String],
        respondedIPAddresses: Set<String>,
        baselineReachableIPAddresses: Set<String>,
        fetchedTemperatures: [String: Double],
        hostnames: [String: String],
        localIPv4Prefixes: Set<String>,
        alertEnabledIPAddresses: Set<String>,
        referenceDate: Date,
        initialState: [String: MinerAlertDeviceState]
    ) -> MinerAlertEvaluation {
        var state = initialState
        var events: [MinerAlertEvent] = []

        for ipAddress in ipAddresses {
            var device = state[ipAddress] ?? MinerAlertDeviceState(
                wasReachable: baselineReachableIPAddresses.contains(ipAddress)
            )
            let name = hostnames[ipAddress] ?? ipAddress
            // Reachability keeps being tracked for every saved miner; only the alerting
            // branches below are gated on this miner's opt-in.
            let alertsEnabled = alertEnabledIPAddresses.contains(ipAddress)

            if respondedIPAddresses.contains(ipAddress) {
                device.consecutiveFailures = 0
                device.wasReachable = true

                if let temperature = fetchedTemperatures[ipAddress], temperature.isFinite {
                    let isHot = temperature >= hotTemperatureThreshold
                    if isHot {
                        if alertsEnabled,
                            device.wasHot != true,
                            cooldownElapsed(device.lastHotAlert, now: referenceDate)
                        {
                            device.lastHotAlert = referenceDate
                            events.append(
                                .hot(
                                    ipAddress: ipAddress,
                                    name: name,
                                    temperature: temperature
                                )
                            )
                        }
                        if alertsEnabled {
                            device.wasHot = true
                        }
                    } else {
                        device.wasHot = false
                    }
                }
            } else if onSameSubnet(
                as: ipAddress,
                localIPv4Prefixes: localIPv4Prefixes
            ) {
                device.consecutiveFailures += 1
                if alertsEnabled,
                    device.wasReachable,
                    device.consecutiveFailures >= failuresBeforeOffline,
                    cooldownElapsed(device.lastOfflineAlert, now: referenceDate)
                {
                    device.wasReachable = false
                    device.lastOfflineAlert = referenceDate
                    events.append(.offline(ipAddress: ipAddress, name: name))
                }
            }

            state[ipAddress] = device
        }

        let savedIPAddresses = Set(ipAddresses)
        state = state.filter { savedIPAddresses.contains($0.key) }
        return MinerAlertEvaluation(state: state, events: events)
    }

    private static func cooldownElapsed(_ last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= alertCooldown
    }

    private static func onSameSubnet(
        as minerAddress: String,
        localIPv4Prefixes: Set<String>
    ) -> Bool {
        guard let prefix = slash24Prefix(of: minerAddress) else { return false }
        return localIPv4Prefixes.contains(prefix)
    }

    private static func slash24Prefix(of address: String) -> String? {
        let host = address.split(separator: ":").first.map(String.init) ?? address
        let octets = host.split(separator: ".")
        guard octets.count == 4 else { return nil }
        return octets.prefix(3).joined(separator: ".") + "."
    }
}
