import Foundation
import SwiftData

@MainActor
final class HistoricalDataRetentionController {
    private let modelContext: ModelContext
    private let retentionInterval: TimeInterval
    private let pruneInterval: TimeInterval
    private let now: @Sendable () -> Date
    private var lastPrunedAtByDeviceKey: [String: Date] = [:]

    init(
        modelContext: ModelContext,
        retentionInterval: TimeInterval = 60 * 60 * 24 * 30,
        pruneInterval: TimeInterval = 60 * 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.modelContext = modelContext
        self.retentionInterval = retentionInterval
        self.pruneInterval = pruneInterval
        self.now = now
    }

    func savePendingChanges(pruningIfNeededFor deviceId: String?) throws {
        try savePendingChanges(pruningIfNeededFor: [deviceId])
    }

    func savePendingChanges(pruningIfNeededFor deviceIds: [String?]) throws {
        let timestamp = now()
        let uniqueDeviceIDs = orderedUniqueDeviceIDs(from: deviceIds)
        let cutoff = timestamp.addingTimeInterval(-retentionInterval)
        var prunedKeys: [String] = []

        for deviceId in uniqueDeviceIDs {
            let pruneKey = pruneKey(for: deviceId)
            guard shouldPruneHistory(for: pruneKey, at: timestamp) else { continue }
            try pruneHistoricalData(for: deviceId, olderThan: cutoff)
            prunedKeys.append(pruneKey)
        }

        try modelContext.save()

        for pruneKey in prunedKeys {
            lastPrunedAtByDeviceKey[pruneKey] = timestamp
        }
    }

    private func shouldPruneHistory(for pruneKey: String, at timestamp: Date) -> Bool {
        guard let lastPrunedAt = lastPrunedAtByDeviceKey[pruneKey] else { return true }
        return timestamp.timeIntervalSince(lastPrunedAt) >= pruneInterval
    }

    private func pruneHistoricalData(for deviceId: String?, olderThan cutoff: Date) throws {
        let predicate: Predicate<HistoricalDataPoint>

        if let deviceId {
            predicate = #Predicate<HistoricalDataPoint> { data in
                data.deviceId == deviceId && data.timestamp < cutoff
            }
        } else {
            predicate = #Predicate<HistoricalDataPoint> { data in
                data.deviceId == nil && data.timestamp < cutoff
            }
        }

        try modelContext.delete(model: HistoricalDataPoint.self, where: predicate)
    }

    private func pruneKey(for deviceId: String?) -> String {
        deviceId ?? "__unassigned__"
    }

    private func orderedUniqueDeviceIDs(from deviceIds: [String?]) -> [String?] {
        var seenPruneKeys: Set<String> = []
        var uniqueDeviceIDs: [String?] = []

        for deviceId in deviceIds {
            let pruneKey = pruneKey(for: deviceId)
            guard seenPruneKeys.insert(pruneKey).inserted else { continue }
            uniqueDeviceIDs.append(deviceId)
        }

        return uniqueDeviceIDs
    }
}
