import Foundation

/// A failed observation does not measure zero. Use reporting miners when any
/// answer; otherwise retain known readings and explicitly describe them as stale.
struct FleetMetricSnapshot: Equatable {
    struct Reading: Equatable {
        let id: String
        let hashrate: Double?
        var power: Double? = nil
        let measuredAt: Date
        let isReachable: Bool?
        var isHashrateReporting: Bool? = nil
        var observedAt: Date? = nil
        var isIncludedInLastKnownTotal: Bool? = nil
    }

    let totalDevices: Int
    let reportingDeviceIDs: Set<String>
    let includedDeviceIDs: Set<String>
    let totalHashrate: Double?
    let totalPower: Double?
    let measuredAt: Date?
    let isStale: Bool

    var isPartial: Bool { includedDeviceIDs.count < totalDevices }

    var statusText: String {
        guard totalHashrate != nil else {
            return reportingDeviceIDs.isEmpty ? "No readings yet" : "Hash rate unavailable"
        }
        if isStale {
            return isPartial
                ? "Last known · \(includedDeviceIDs.count) of \(totalDevices) miners · stale"
                : "Last known · stale"
        }
        if includedDeviceIDs.count < reportingDeviceIDs.count {
            return "\(includedDeviceIDs.count) of \(totalDevices) miners with hash rate"
        }
        return "\(reportingDeviceIDs.count) of \(totalDevices) miners reporting"
    }

    var compactStatusText: String {
        guard totalHashrate != nil else { return "Unavailable" }
        if isStale {
            return isPartial ? "\(includedDeviceIDs.count)/\(totalDevices) stale" : "Stale"
        }
        return isPartial ? "\(includedDeviceIDs.count)/\(totalDevices) reporting" : ""
    }

    func rowStatusText(for reading: Reading) -> String {
        guard let hashrate = reading.hashrate, hashrate.isFinite, hashrate >= 0 else {
            return "Hash rate unavailable"
        }
        guard includedDeviceIDs.contains(reading.id) else {
            return "Last known · excluded from total"
        }
        return isStale ? "Last known · stale" : "Reporting"
    }

    static func make(
        readings: [Reading],
        totalDevices: Int,
        referenceDate: Date = Date()
    ) -> Self {
        // Matches the existing widget freshness window. Age alone never changes
        // a measured value; it only determines whether to call it last known.
        let cutoff = referenceDate.addingTimeInterval(-30 * 60)
        let reporting = readings.filter {
            $0.isReachable == true && ($0.observedAt ?? $0.measuredAt) >= cutoff
        }
        let isStale = reporting.isEmpty
        let knownReadings = readings.filter {
            guard let hashrate = $0.hashrate else { return false }
            return hashrate.isFinite && hashrate >= 0
        }
        let newestMeasurement = knownReadings.map(\.measuredAt).max()
        let included: [Reading]
        if isStale, readings.contains(where: { $0.isIncludedInLastKnownTotal != nil }) {
            // A failed refresh must not bring a miner back into the total after
            // a prior partial refresh excluded it. Membership travels with the
            // cached reading, including when its address changes.
            included = knownReadings.filter { $0.isIncludedInLastKnownTotal == true }
        } else if isStale, let newestMeasurement {
            // Older caches have no recorded membership. Infer their last
            // observation window without combining a recent miner with one
            // that stopped reporting days earlier.
            let lastKnownCutoff = newestMeasurement.addingTimeInterval(-30 * 60)
            included = knownReadings.filter { $0.measuredAt >= lastKnownCutoff }
        } else {
            let reportingIDs = Set(reporting.map(\.id))
            included = knownReadings.filter {
                reportingIDs.contains($0.id) && $0.isHashrateReporting != false
            }
        }
        let power = included.compactMap(\.power).filter { $0.isFinite && $0 >= 0 }
        return Self(
            totalDevices: max(totalDevices, readings.count),
            reportingDeviceIDs: Set(reporting.map(\.id)),
            includedDeviceIDs: Set(included.map(\.id)),
            totalHashrate: included.isEmpty ? nil : included.compactMap(\.hashrate).reduce(0, +),
            totalPower: power.isEmpty ? nil : power.reduce(0, +),
            // A total combines readings; the oldest included measurement bounds
            // its freshness. Never manufacture a timestamp for an absent reading.
            measuredAt: included.map(\.measuredAt).min(),
            isStale: isStale
        )
    }
}
