import Foundation
import SwiftData

/// Rewrites stored history when saved miners change IP addresses, so charts and
/// recaps keep their past when DHCP moves them.
///
/// Runs on its own context so a large history never blocks the main actor; batches
/// keep memory flat regardless of how many points a miner has accumulated.
@ModelActor
actor HistoricalDataRelocator {
    private static let batchSize = 500

    func relocate(
        _ currentByPrevious: [String: String],
        before cutoff: Date,
        operationID: String
    ) throws {
        for (previous, current) in currentByPrevious.sorted(by: { $0.key < $1.key })
        where previous != current {
            let previousDeviceId: String? = previous
            let currentDeviceId: String? = current
            let currentOperationID: String? = operationID
            var descriptor = FetchDescriptor<HistoricalDataPoint>(
                predicate: #Predicate<HistoricalDataPoint> { data in
                    data.deviceId == previousDeviceId
                        && data.timestamp < cutoff
                        && (data.relocationOperationID == nil
                            || data.relocationOperationID != currentOperationID)
                }
            )
            descriptor.fetchLimit = Self.batchSize

            do {
                while true {
                    let batch = try modelContext.fetch(descriptor)
                    guard !batch.isEmpty else { break }
                    for dataPoint in batch {
                        dataPoint.deviceId = currentDeviceId
                        dataPoint.relocationOperationID = operationID
                    }
                    try modelContext.save()
                }
            } catch {
                modelContext.rollback()
                throw error
            }
        }
    }
}
