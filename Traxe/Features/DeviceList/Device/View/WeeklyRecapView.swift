import Foundation
import SwiftData
import SwiftUI

struct WeeklyRecapFleetDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let poolName: String?
    let currentHashrate: Double
}

struct WeeklyRecapHistorySampleRecord: Sendable, Equatable {
    let timestamp: Date
    let hashrate: Double
    let temperature: Double
    let deviceID: String?

    init(point: HistoricalDataPoint) {
        self.timestamp = point.timestamp
        self.hashrate = point.hashrate
        self.temperature = point.temperature
        self.deviceID = point.deviceId
    }
}

enum WeeklyRecapHistoryQuery {
    @MainActor
    static func fetchSampleRecords(
        in modelContext: ModelContext,
        for deviceID: String,
        startDate: Date,
        endDateExclusive: Date
    ) throws -> [WeeklyRecapHistorySampleRecord] {
        let descriptor = FetchDescriptor<HistoricalDataPoint>(
            predicate: #Predicate<HistoricalDataPoint> { point in
                point.timestamp >= startDate
                    && point.timestamp < endDateExclusive
                    && point.deviceId == deviceID
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )

        return try modelContext.fetch(descriptor).map(WeeklyRecapHistorySampleRecord.init(point:))
    }

    @MainActor
    static func fetchSampleRecords(
        in modelContext: ModelContext,
        for deviceIDs: [String],
        startDate: Date,
        endDateExclusive: Date
    ) throws -> [WeeklyRecapHistorySampleRecord] {
        let uniqueDeviceIDs = orderedUniqueDeviceIDs(from: deviceIDs)
        guard !uniqueDeviceIDs.isEmpty else { return [] }

        var sampleRecords: [WeeklyRecapHistorySampleRecord] = []

        for deviceID in uniqueDeviceIDs {
            try sampleRecords.append(
                contentsOf: fetchSampleRecords(
                    in: modelContext,
                    for: deviceID,
                    startDate: startDate,
                    endDateExclusive: endDateExclusive
                )
            )
        }

        sampleRecords.sort { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return (lhs.deviceID ?? "") < (rhs.deviceID ?? "")
            }
            return lhs.timestamp < rhs.timestamp
        }
        return sampleRecords
    }

    private static func orderedUniqueDeviceIDs(from deviceIDs: [String]) -> [String] {
        var seen: Set<String> = []
        var orderedDeviceIDs: [String] = []

        for deviceID in deviceIDs where seen.insert(deviceID).inserted {
            orderedDeviceIDs.append(deviceID)
        }

        return orderedDeviceIDs
    }
}

struct WeeklyRecapView: View {
    enum Scope {
        case device(deviceID: String, deviceName: String, poolName: String?)
        case fleet(devices: [WeeklyRecapFleetDevice])
    }

    let scope: Scope
    private let initialLatestBlockHeightsByPoolSlug: [String: Int]

    @Environment(\.modelContext) private var modelContext
    @State private var recap: WeeklyRecap?
    @State private var fleetRecaps: [WeeklyRecapFleetRecap] = []
    @State private var isLoading = false
    @State private var expandedFleetDeviceIDs: Set<String> = []
    @State private var latestBlockHeightsByPoolSlug: [String: Int] = [:]

    private let poolBlockLookupService = PoolBlockLookupService()

    init(
        scope: Scope,
        initialLatestBlockHeightsByPoolSlug: [String: Int] = [:]
    ) {
        self.scope = scope
        self.initialLatestBlockHeightsByPoolSlug = initialLatestBlockHeightsByPoolSlug
        self._latestBlockHeightsByPoolSlug = State(
            initialValue: initialLatestBlockHeightsByPoolSlug
        )
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.tertiarySystemBackground),
                    Color(.secondarySystemBackground),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    WeeklyRecapContextHeaderView(
                        scope: scope,
                        weekTitleText: weekTitleText,
                        fleetPoolAllocations: fleetHeaderPoolAllocations,
                        latestBlockHeightsByPoolSlug: latestBlockHeightsByPoolSlug
                    )

                    if isLoading {
                        ProgressView("Loading weekly recap…")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                    } else {
                        content
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Weekly Recap")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadRecap() }
    }

    @ViewBuilder
    private var content: some View {
        switch scope {
        case .device:
            if let recap {
                WeeklyRecapDetailContentView(
                    recap: recap,
                    showDateRange: false
                )
            } else {
                WeeklyRecapMessageCardView(title: nil, message: emptyStateText)
            }
        case .fleet:
            if fleetRecaps.isEmpty {
                WeeklyRecapMessageCardView(title: nil, message: emptyStateText)
            } else {
                WeeklyRecapFleetContentView(
                    fleetRecaps: fleetRecaps,
                    expandedFleetDeviceIDs: expandedFleetDeviceIDs,
                    areAllFleetSectionsExpanded: areAllFleetSectionsExpanded,
                    deviceHistoryEmptyStateText: deviceHistoryEmptyStateText,
                    toggleAllFleetSections: toggleAllFleetSections,
                    toggleFleetSection: toggleFleetSection(deviceID:)
                )
            }
        }
    }

    private var areAllFleetSectionsExpanded: Bool {
        let allIDs = Set(fleetRecaps.map(\.id))
        return !allIDs.isEmpty && allIDs.isSubset(of: expandedFleetDeviceIDs)
    }

    private var fleetHeaderPoolAllocations: [WeeklyRecapPoolAllocation] {
        switch scope {
        case .device:
            return []
        case .fleet(let devices):
            if fleetRecaps.isEmpty {
                return WeeklyRecapPoolAllocationBuilder.buildFleetTotals(
                    from: devices.map { device in
                        (poolDisplayName: device.poolName, totalHashrate: device.currentHashrate)
                    }
                )
            }

            return fleetPoolAllocations(for: fleetRecaps)
        }
    }

    private func toggleAllFleetSections() {
        let allIDs = Set(fleetRecaps.map(\.id))
        guard !allIDs.isEmpty else { return }

        withAnimation(.easeInOut(duration: 0.25)) {
            if allIDs.isSubset(of: expandedFleetDeviceIDs) {
                expandedFleetDeviceIDs.subtract(allIDs)
            } else {
                expandedFleetDeviceIDs.formUnion(allIDs)
            }
        }
    }

    private func toggleFleetSection(deviceID: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            if expandedFleetDeviceIDs.contains(deviceID) {
                expandedFleetDeviceIDs.remove(deviceID)
            } else {
                expandedFleetDeviceIDs.insert(deviceID)
            }
        }
    }

    @MainActor
    private func loadRecap() async {
        isLoading = true
        latestBlockHeightsByPoolSlug = initialLatestBlockHeightsByPoolSlug
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        var fleetPoolAllocationsToRefresh: [WeeklyRecapPoolAllocation] = []

        guard
            let startDate = calendar.date(byAdding: .day, value: -6, to: todayStart),
            let endDateExclusive = calendar.date(byAdding: .day, value: 1, to: todayStart)
        else {
            recap = nil
            isLoading = false
            return
        }

        do {
            switch scope {
            case .device(let deviceID, _, _):
                let deviceSampleRecords = try WeeklyRecapHistoryQuery.fetchSampleRecords(
                    in: modelContext,
                    for: deviceID,
                    startDate: startDate,
                    endDateExclusive: endDateExclusive
                )
                let deviceSamples = deviceSampleRecords.map { record in
                    WeeklyRecapSample(
                        timestamp: record.timestamp,
                        hashrate: record.hashrate,
                        temperature: record.temperature
                    )
                }
                recap = await Task.detached(priority: .userInitiated) {
                    WeeklyRecapBuilder.build(from: deviceSamples, now: now, calendar: calendar)
                }.value
                fleetRecaps = []
                expandedFleetDeviceIDs = []
            case .fleet(let devices):
                recap = nil
                let sampleRecords = try WeeklyRecapHistoryQuery.fetchSampleRecords(
                    in: modelContext,
                    for: devices.map(\.id),
                    startDate: startDate,
                    endDateExclusive: endDateExclusive
                )
                let loadedFleetRecaps = await Task.detached(priority: .userInitiated) {
                    let pointsByDeviceID = Dictionary(grouping: sampleRecords) { record in
                        record.deviceID ?? ""
                    }
                    return devices.map { device in
                        let deviceSamples = (pointsByDeviceID[device.id] ?? []).map { record in
                            WeeklyRecapSample(
                                timestamp: record.timestamp,
                                hashrate: record.hashrate,
                                temperature: record.temperature
                            )
                        }
                        let recap = WeeklyRecapBuilder.build(
                            from: deviceSamples,
                            now: now,
                            calendar: calendar
                        )
                        return WeeklyRecapFleetRecap(
                            id: device.id,
                            name: device.name,
                            poolName: device.poolName,
                            currentHashrate: device.currentHashrate,
                            recap: recap
                        )
                    }
                }.value
                fleetRecaps = loadedFleetRecaps
                let loadedIDs = Set(loadedFleetRecaps.map(\.id))
                var retainedExpansion = expandedFleetDeviceIDs.intersection(loadedIDs)
                if retainedExpansion.isEmpty, let firstID = loadedFleetRecaps.first?.id {
                    retainedExpansion.insert(firstID)
                }
                expandedFleetDeviceIDs = retainedExpansion
                fleetPoolAllocationsToRefresh = fleetPoolAllocations(for: loadedFleetRecaps)
            }
        } catch {
            recap = nil
            fleetRecaps = []
            expandedFleetDeviceIDs = []
        }

        isLoading = false

        guard !ProcessInfo.isPreview, !fleetPoolAllocationsToRefresh.isEmpty else { return }

        Task {
            await loadFleetPoolLastBlockHeights(for: fleetPoolAllocationsToRefresh)
        }
    }

    @MainActor
    private func loadFleetPoolLastBlockHeights(for allocations: [WeeklyRecapPoolAllocation]) async {
        let poolSlugs = allocations.compactMap(\.poolSlug)
        guard !poolSlugs.isEmpty else { return }
        let latestBlockHeights = await poolBlockLookupService.fetchLatestBlockHeights(
            for: poolSlugs
        )
        withAnimation(WeeklyRecapLastBlockRevealView.revealAnimation) {
            latestBlockHeightsByPoolSlug = latestBlockHeights
        }
    }

    private func fleetPoolAllocations(
        for fleetRecaps: [WeeklyRecapFleetRecap]
    ) -> [WeeklyRecapPoolAllocation] {
        WeeklyRecapPoolAllocationBuilder.buildFleetTotals(
            from: fleetRecaps.map { recap in
                (
                    poolDisplayName: recap.poolName,
                    totalHashrate: recap.recap?.averageHashrate ?? recap.currentHashrate
                )
            }
        )
    }

    private var weekTitleText: String {
        switch scope {
        case .device:
            if let recap {
                return WeeklyRecapChartPresenter.dateRangeText(for: recap)
            }
        case .fleet:
            if let recap = fleetRecaps.compactMap(\.recap).first {
                return WeeklyRecapChartPresenter.dateRangeText(for: recap)
            }
        }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        return
            "\(WeeklyRecapChartPresenter.shortDate(startDate)) - \(WeeklyRecapChartPresenter.shortDate(todayStart))"
    }

    private var emptyStateText: String {
        switch scope {
        case .device:
            return
                "Not enough device history yet. Keep the app open while mining to generate weekly recap data."
        case .fleet:
            return
                "Not enough fleet history yet. Open your miners from the main screen to start collecting recap data."
        }
    }

    private var deviceHistoryEmptyStateText: String {
        "Not enough device history yet. Keep the app open while mining to generate weekly recap data."
    }
}

#Preview("Weekly Recap - Fleet Pools") {
    let container = makeWeeklyRecapPreviewContainer()
    seedWeeklyRecapPreviewData(in: container.mainContext)

    return NavigationStack {
        WeeklyRecapView(
            scope: .fleet(
                devices: [
                    WeeklyRecapFleetDevice(
                        id: "192.168.1.101",
                        name: "nerdqaxe++",
                        poolName: "mine.ocean.xyz (65%) • publicpool.io (35%)",
                        currentHashrate: 20_600
                    ),
                    WeeklyRecapFleetDevice(
                        id: "192.168.1.102",
                        name: "bitaxe",
                        poolName: "solo.ckpool.org",
                        currentHashrate: 720
                    ),
                ]
            ),
            initialLatestBlockHeightsByPoolSlug: [
                "ocean": 941_416,
                "publicpool": 839_405,
            ]
        )
    }
    .modelContainer(container)
}

private func makeWeeklyRecapPreviewContainer() -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)

    do {
        return try ModelContainer(for: HistoricalDataPoint.self, configurations: config)
    } catch {
        fatalError("Failed to create weekly recap preview container: \(error)")
    }
}

private func seedWeeklyRecapPreviewData(in modelContext: ModelContext) {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let previewDevices: [(id: String, baseHashrate: Double, baseTemperature: Double)] = [
        ("192.168.1.101", 20_600, 60),
        ("192.168.1.102", 720, 64),
    ]

    for dayOffset in 0..<7 {
        guard let day = calendar.date(byAdding: .day, value: dayOffset - 6, to: today) else {
            continue
        }

        for device in previewDevices {
            for sampleIndex in 0..<3 {
                let hourOffset = 8 + (sampleIndex * 4)
                let timestamp = calendar.date(byAdding: .hour, value: hourOffset, to: day) ?? day
                let hashrateDrift = Double((dayOffset + sampleIndex) % 3 - 1)
                let temperatureDrift = Double((dayOffset + sampleIndex) % 4 - 1)

                modelContext.insert(
                    HistoricalDataPoint(
                        timestamp: timestamp,
                        hashrate: device.baseHashrate
                            + (hashrateDrift * device.baseHashrate * 0.025),
                        temperature: device.baseTemperature + temperatureDrift,
                        deviceId: device.id
                    )
                )
            }
        }
    }

    try? modelContext.save()
}
