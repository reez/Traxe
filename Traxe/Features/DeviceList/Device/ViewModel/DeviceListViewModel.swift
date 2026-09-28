import Combine
import Observation
import SwiftData
import SwiftUI
import TipKit
import UIKit
import WidgetKit

@Observable
@MainActor
final class DeviceListViewModel {
    struct Dependencies {
        struct DeviceManagementClient {
            var checkDevice: @Sendable (_ ip: String) async throws -> DiscoveredDevice
            var deleteDevice: @Sendable (_ ipAddressToDelete: String) throws -> Void
            var reorderDevices: @Sendable (_ devices: [SavedDevice]) throws -> Void
            var recordMACAddress:
                @Sendable (_ macAddress: String, _ ipAddress: String) throws -> Void = { _, _ in }
            var scanLocalNetwork:
                @Sendable (_ excludedIPAddresses: Set<String>) async -> [DiscoveredDevice] = {
                    _ in []
                }
            var relocateDevices:
                @Sendable (_ discoveredDevices: [DiscoveredDevice]) throws -> [DeviceRelocation] = {
                    _ in []
                }

            static let live = Self(
                checkDevice: { ip in
                    try await DeviceManagementService.checkDevice(
                        ip: ip,
                        timeout: 2.0,
                        retryOnTimeout: false
                    )
                },
                deleteDevice: { ipAddressToDelete in
                    try DeviceManagementService.deleteDevice(ipAddressToDelete: ipAddressToDelete)
                },
                reorderDevices: { devices in
                    try DeviceManagementService.reorderDevices(devices)
                },
                recordMACAddress: { macAddress, ipAddress in
                    try DeviceManagementService.recordMACAddress(macAddress, forDeviceAt: ipAddress)
                },
                scanLocalNetwork: { excludedIPAddresses in
                    await DeviceManagementService.scanLocalNetwork(excluding: excludedIPAddresses)
                },
                relocateDevices: { discoveredDevices in
                    try DeviceManagementService.relocateDevices(matching: discoveredDevices)
                }
            )
        }

        var deviceManagement: DeviceManagementClient
        var reloadWidget: @Sendable () -> Void
        var autoRefreshOnLoad: Bool
        /// A subnet scan for missing miners is expensive, and a miner that is simply
        /// powered off would otherwise trigger one on every refresh.
        var relocationScanMinimumInterval: TimeInterval = 120

        static let live = Self(
            deviceManagement: .live,
            reloadWidget: {
                WidgetCenter.shared.reloadTimelines(ofKind: "TraxeWidget")
            },
            autoRefreshOnLoad: true
        )
    }

    var savedDevices: [SavedDevice] = []
    var totalHashRate: Double = 0.0
    var totalPower: Double = 0.0
    var bestOverallDiff: Double = 0.0
    var isLoadingAggregatedStats = false
    var deviceMetrics: [String: DeviceMetrics] = [:]
    var isEditMode = false
    var fleetAISummary: AISummary?
    var lastDataUpdate: Date = Date()
    var reachableIPs: Set<String> = []
    /// Miners DHCP moved in the most recent change to `savedDevices`, previous address
    /// to current, so navigation can follow a selected miner instead of dropping it.
    private(set) var recentRelocations: [String: String] = [:]
    var lastSeenWhatsNewVersion: String? = nil
    var deviceGridSortOption: DeviceGridSortOption = .savedOrder {
        didSet {
            defaults.set(
                deviceGridSortOption.rawValue,
                forKey: StorageKeys.deviceGridSortOption
            )
        }
    }
    private var hasCompletedAggregatedStatsRefresh = false
    private var cachedFleetHealth: FleetHealthCacheEntry?

    private let dependencies: Dependencies
    private let defaults: UserDefaults
    private var aiAnalysisService: AIAnalysisService?
    private let metricsCache: DeviceMetricsCache
    private var modelContext: ModelContext?
    private var historicalDataRetentionController: HistoricalDataRetentionController?
    private var historicalDataRelocator: HistoricalDataRelocator?
    private var lastRelocationScanAt: Date?

    private final class WeakModelContext {
        weak var value: ModelContext?

        init(_ value: ModelContext) {
            self.value = value
        }
    }

    private static var historyRelocationTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private static var historyModelContexts: [ObjectIdentifier: [WeakModelContext]] = [:]

    private enum StorageKeys {
        static let lastSeenWhatsNewVersion = "lastSeenWhatsNewVersion"
        static let deviceGridSortOption = "deviceGridSortOption"
        static let cachedFleetHealthSnapshot = "cachedFleetHealthSnapshotV1"
        static let pendingHistoryRelocations = "pendingHistoryRelocationsV1"
        static let lastHistoryRelocationAddresses = "lastHistoryRelocationAddressesByMACV1"
        static let completedHistoryRelocations = "completedHistoryRelocationsV1"
    }

    private enum Support {
        static let emailAddress = "ramsden.matthew@gmail.com"
        static let emailSubject = "Traxe - Support"
    }

    private enum OpenSource {
        static let repoURL = "https://github.com/reez/Traxe"
    }

    // Minimal cached fleet summary entry for instant display on launch
    private struct FleetSummaryCacheEntry: Codable {
        let content: String
        let generatedAt: Date
        let deviceCount: Int
    }

    private struct FleetHealthCacheEntry: Codable {
        let snapshot: FleetHealthSnapshot
        let generatedAt: Date
        let deviceIPAddresses: [String]
    }

    private struct HistoryRelocationJob: Codable {
        let id: String
        let currentByPrevious: [String: String]
        let cutoff: Date
    }

    init(
        defaults: UserDefaults = UserDefaults(suiteName: "group.matthewramsden.traxe") ?? .standard,
        dependencies: Dependencies = .live
    ) {
        self.dependencies = dependencies
        self.defaults = defaults
        self.metricsCache = DeviceMetricsCache(defaults: defaults)
        if #available(iOS 18.0, macOS 15.0, *) {
            self.aiAnalysisService = AIAnalysisService()
        }
        self.lastSeenWhatsNewVersion = defaults.string(
            forKey: StorageKeys.lastSeenWhatsNewVersion
        )
        self.deviceGridSortOption =
            defaults.string(forKey: StorageKeys.deviceGridSortOption)
            .flatMap(DeviceGridSortOption.init(rawValue:)) ?? .savedOrder
        loadDevices()
        cachedFleetHealth = loadCachedFleetHealth()
        loadCacheAndComputeTotals()
        // If we couldn't build a summary from cached metrics (e.g., cache is empty),
        // fall back to the last persisted fleet summary so the section still has content.
        if fleetAISummary == nil, let cached = loadCachedFleetSummary() {
            self.fleetAISummary = cached
        }
    }

    var shouldShowWhatsNewTip: Bool {
        let currentKey = WhatsNewConfig.currentWhatsNewKey()
        return WhatsNewConfig.isEnabledForCurrentBuild
            && lastSeenWhatsNewVersion != currentKey
    }

    var fleetHealthSnapshot: FleetHealthSnapshot {
        if isFleetHealthRefreshing, let snapshot = matchingCachedFleetHealthSnapshot {
            return snapshot
        }

        return liveFleetHealthSnapshot
    }

    var isFleetHealthLoading: Bool {
        !savedDevices.isEmpty && !hasCompletedAggregatedStatsRefresh
            && matchingCachedFleetHealthSnapshot == nil
    }

    var isFleetHealthRefreshing: Bool {
        !savedDevices.isEmpty && !hasCompletedAggregatedStatsRefresh
            && matchingCachedFleetHealthSnapshot != nil
    }

    private var liveFleetHealthSnapshot: FleetHealthSnapshot {
        FleetHealthSnapshot.make(
            devices: savedDevices,
            metricsByIP: deviceMetrics,
            reachableIPs: reachableIPs,
            isRefreshing: isLoadingAggregatedStats
        )
    }

    private var matchingCachedFleetHealthSnapshot: FleetHealthSnapshot? {
        guard let cachedFleetHealth,
            cachedFleetHealth.deviceIPAddresses == currentDeviceIPAddresses
        else { return nil }

        return cachedFleetHealth.snapshot
    }

    private var currentDeviceIPAddresses: [String] {
        savedDevices.map(\.ipAddress).sorted()
    }

    func loadDevices() {
        let previousDevices = savedDevices
        let previousIPAddresses = Set(previousDevices.map(\.ipAddress))

        var loadedDevices: [SavedDevice] = []
        if let data = defaults.data(forKey: "savedDevices"),
            let decoded = try? JSONDecoder().decode([SavedDevice].self, from: data)
        {
            loadedDevices = decoded
            if decoded.contains(where: \.needsIdentifierMigration),
                let migratedData = try? JSONEncoder().encode(decoded),
                defaults.data(forKey: "savedDevices") == data
            {
                defaults.set(migratedData, forKey: "savedDevices")
            }
            // The service persists relocation records in the same value as the new
            // addresses. Read the latest value in case the ID migration rewrote it.
            if let currentData = defaults.data(forKey: "savedDevices"),
                let currentDevices = try? JSONDecoder().decode(
                    [SavedDevice].self,
                    from: currentData
                )
            {
                loadedDevices = recoverRecordedRelocations(
                    in: currentDevices,
                    encodedData: currentData
                )
            }
        }

        followRelocatedDevices(from: previousDevices, to: loadedDevices)
        self.savedDevices = loadedDevices
        updateFleetHealthRefreshState(previousIPAddresses: previousIPAddresses)
        saveIPsAndReloadWidget()
        scheduleAggregatedStatsRefreshIfNeeded()
    }

    private func updateFleetHealthRefreshState(previousIPAddresses: Set<String>) {
        let currentIPAddresses = Set(savedDevices.map(\.ipAddress))
        if currentIPAddresses != previousIPAddresses {
            hasCompletedAggregatedStatsRefresh = false
            cachedFleetHealth = loadCachedFleetHealth()
        }
    }

    private func scheduleAggregatedStatsRefreshIfNeeded() {
        guard dependencies.autoRefreshOnLoad else { return }
        Task { await updateAggregatedStats() }
    }

    func configureModelContextIfNeeded(_ modelContext: ModelContext) -> Bool {
        guard self.modelContext == nil else { return false }
        self.modelContext = modelContext
        self.historicalDataRetentionController = HistoricalDataRetentionController(
            modelContext: modelContext
        )
        self.historicalDataRelocator = HistoricalDataRelocator(
            modelContainer: modelContext.container
        )
        let containerID = ObjectIdentifier(modelContext.container)
        var contexts = Self.historyModelContexts[containerID] ?? []
        contexts.removeAll { $0.value == nil }
        if !contexts.contains(where: { $0.value === modelContext }) {
            contexts.append(WeakModelContext(modelContext))
        }
        Self.historyModelContexts[containerID] = contexts
        scheduleHistoryRelocations()
        return true
    }

    func loadCacheAndComputeTotals() {
        // Load cached metrics
        let cachedMetrics = metricsCache.loadAll()
        // Prune cache to only include current devices
        let currentIPs = savedDevices.map { $0.ipAddress }
        metricsCache.prune(ips: currentIPs)
        let currentIPSet = Set(currentIPs)
        let prunedMetrics = cachedMetrics.filter { currentIPSet.contains($0.key) }

        // Apply pruned cache to current devices (merge defensively, avoid zeroing temps)
        for device in savedDevices {
            if let cached = prunedMetrics[device.ipAddress] {
                var merged = DeviceMetrics(from: cached)
                if let existing = deviceMetrics[device.ipAddress] {
                    // If cached temp is missing/zero but we have a non-zero in-memory temp, keep it
                    if (cached.temperature ?? 0.0) == 0.0, existing.temperature > 0.0 {
                        merged.temperature = existing.temperature
                        merged.isTemperatureKnown = existing.isTemperatureKnown
                    }
                    if !merged.isHashrateKnown, existing.isHashrateKnown {
                        merged.hashrate = existing.hashrate
                        merged.isHashrateKnown = true
                    }
                    if !merged.isMiningPausedKnown, existing.isMiningPausedKnown {
                        merged.isMiningPaused = existing.isMiningPaused
                        merged.isMiningPausedKnown = true
                    }
                }
                deviceMetrics[device.ipAddress] = merged
            }
        }

        // Compute totals from cached metrics
        computeTotals()

    }

    private func computeTotals() {
        var currentTotalHashRate: Double = 0.0
        var currentTotalPower: Double = 0.0
        var currentBestDiff: Double = 0.0

        for metrics in deviceMetrics.values {
            currentTotalHashRate += metrics.hashrate
            currentTotalPower += metrics.power
            currentBestDiff = max(currentBestDiff, metrics.bestDifficulty)
        }

        totalHashRate = currentTotalHashRate
        totalPower = currentTotalPower
        bestOverallDiff = currentBestDiff
        lastDataUpdate = Date()

        // Keep fleet summary in lockstep with totals based on the same snapshot
        if AIFeatureFlags.isAvailable,
            AIFeatureFlags.isEnabledByUser,
            savedDevices.count > 1,
            let summary = buildFleetSummaryFromMetrics(Array(deviceMetrics.values))
        {
            self.fleetAISummary = summary
        }
    }

    func markWhatsNewTipSeen() {
        let currentKey = WhatsNewConfig.currentWhatsNewKey()
        lastSeenWhatsNewVersion = currentKey
        defaults.set(currentKey, forKey: StorageKeys.lastSeenWhatsNewVersion)
    }

    func handleWhatsNewTipStatus(_ status: Tips.Status) {
        guard case let .invalidated(reason) = status else { return }
        if shouldRecordCompletion(for: reason) {
            markWhatsNewTipSeen()
        }
    }

    func sendSupportEmail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Support.emailAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: Support.emailSubject)
        ]

        guard let url = components.url else {
            return
        }

        UIApplication.shared.open(url)
    }

    func openSourceRepo() {
        guard let url = URL(string: OpenSource.repoURL) else {
            return
        }

        UIApplication.shared.open(url)
    }

    private func shouldRecordCompletion(for reason: Tips.InvalidationReason) -> Bool {
        switch reason {
        case .actionPerformed, .tipClosed:
            return true
        default:
            return false
        }
    }

    func deleteDevice(at offsets: IndexSet) {
        let devicesToDelete = offsets.map { savedDevices[$0] }
        deleteDevices(devicesToDelete)
    }

    func deleteDevices(withIPAddresses ipAddresses: Set<String>) {
        let devicesToDelete = savedDevices.filter { ipAddresses.contains($0.ipAddress) }
        deleteDevices(devicesToDelete)
    }

    private func deleteDevices(_ devicesToDelete: [SavedDevice]) {
        recentRelocations = [:]
        for device in devicesToDelete {
            do {
                try dependencies.deviceManagement.deleteDevice(device.ipAddress)
                savedDevices.removeAll { $0.ipAddress == device.ipAddress }
                deviceMetrics.removeValue(forKey: device.ipAddress)
                saveIPsAndReloadWidget()
            } catch {
            }
        }

        // Prune cache and recompute totals
        let currentIPs = savedDevices.map { $0.ipAddress }
        metricsCache.prune(ips: currentIPs)
        computeTotals()

        Task { await updateAggregatedStats() }
    }

    func updateAggregatedStats() async {
        await refreshAggregatedStats()
        await relocateMissingDevicesIfNeeded()
        scheduleHistoryRelocations()
    }

    private func refreshAggregatedStats() async {
        // Prevent overlapping refreshes
        if isLoadingAggregatedStats {
            return
        }
        // Keep existing fleet AI summary visible during refresh

        isLoadingAggregatedStats = true

        // Capture current IPs to avoid touching actor state off the main actor
        let devicesSnapshot = savedDevices
        let checkDevice = dependencies.deviceManagement.checkDevice

        // Perform network fetches off the main actor, then apply results on main
        let fetchedResults: [(String, DeviceMetrics?)] = await Task.detached(
            priority: .userInitiated
        ) {
            await withTaskGroup(of: (String, DeviceMetrics?).self) { group in
                for device in devicesSnapshot {
                    group.addTask {
                        do {
                            let discoveredDevice = try await checkDevice(device.ipAddress)
                            // Inline parse to avoid touching main-actor method
                            let parsedDifficulty: Double = {
                                let multipliers: [Character: Double] = [
                                    "K": 1_000,
                                    "M": 1_000_000,
                                    "G": 1_000_000_000,
                                    "T": 1_000_000_000_000,
                                    "P": 1_000_000_000_000_000,
                                ]
                                let trimmed = discoveredDevice.bestDiff.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                                guard !trimmed.isEmpty else { return 0.0 }
                                guard let lastChar = trimmed.last else { return 0.0 }
                                var numeric = trimmed
                                var mult: Double = 1.0
                                if let suffix = lastChar.uppercased().first,
                                    let m = multipliers[suffix]
                                {
                                    mult = m
                                    numeric = String(trimmed.dropLast())
                                } else if lastChar.isLetter {
                                    return 0.0
                                }
                                let cleaned =
                                    numeric
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .replacing(",", with: "")
                                guard let value = Double(cleaned) else { return 0.0 }
                                return value / 1_000_000.0 * mult
                            }()

                            let metrics = DeviceMetrics(
                                hashrate: discoveredDevice.hashrate,
                                temperature: discoveredDevice.temperature,
                                power: discoveredDevice.power,
                                bestDifficulty: parsedDifficulty,
                                poolURL: discoveredDevice.poolURL,
                                hostname: discoveredDevice.name,
                                blockHeight: discoveredDevice.blockHeight,
                                networkDifficulty: discoveredDevice.networkDifficulty,
                                isHashrateKnown: discoveredDevice.isHashrateKnown,
                                isTemperatureKnown: discoveredDevice.isTemperatureKnown,
                                isMiningPaused: discoveredDevice.isMiningPaused,
                                isMiningPausedKnown: discoveredDevice.isMiningPausedKnown,
                                macAddress: discoveredDevice.macAddress
                            )
                            return (device.ipAddress, metrics)
                        } catch {
                            return (device.ipAddress, nil)
                        }
                    }
                }

                var results: [(String, DeviceMetrics?)] = []
                for await item in group { results.append(item) }
                return results
            }
        }.value

        // Apply fetched results on main actor
        let activeIPs = Set(savedDevices.map(\.ipAddress))
        // Drop any cached metrics for devices that were removed mid-refresh so totals stay accurate
        let orphanedIPs = deviceMetrics.keys.filter { !activeIPs.contains($0) }
        for ip in orphanedIPs {
            deviceMetrics.removeValue(forKey: ip)
        }

        var newReachables: Set<String> = []
        var successfulFetchCount = 0
        var successfulSamples: [(deviceId: String, metrics: DeviceMetrics)] = []
        for (ipAddress, metrics) in fetchedResults {
            guard activeIPs.contains(ipAddress), let metrics else { continue }

            // The MAC address is the miner's identity. Learn it the first time a saved
            // miner answers; when a different miner answers at this address, DHCP has
            // reassigned the address and the saved miner is missing, not online.
            if let fetchedMACAddress = metrics.macAddress,
                let index = savedDevices.firstIndex(where: { $0.ipAddress == ipAddress })
            {
                if let savedMACAddress = savedDevices[index].macAddress {
                    guard savedMACAddress == fetchedMACAddress else { continue }
                } else {
                    recordMACAddress(fetchedMACAddress, forDeviceAt: index)
                }
            }

            deviceMetrics[ipAddress] = metrics
            newReachables.insert(ipAddress)
            successfulFetchCount += 1
            successfulSamples.append((deviceId: ipAddress, metrics: metrics))
        }
        // Atomically update reachable set to avoid mid-refresh greying
        reachableIPs = newReachables
        computeTotals()
        persistHistoricalSamples(successfulSamples)
        hasCompletedAggregatedStatsRefresh = true

        isLoadingAggregatedStats = false

        saveCachedFleetHealthSnapshot(liveFleetHealthSnapshot)
        // Save all current metrics to cache
        saveCacheFromCurrentMetrics()
        // No need to regenerate summary here; computeTotals() already keeps it in sync

        if successfulFetchCount > 0 {
            dependencies.reloadWidget()
        }
    }

    private func saveCacheFromCurrentMetrics() {
        var cacheMetrics: [String: CachedDeviceMetrics] = [:]

        for (ipAddress, metrics) in deviceMetrics {
            var cached = CachedDeviceMetrics(from: metrics)
            if cached.macAddress == nil {
                cached.macAddress = savedDevices.first(where: { $0.ipAddress == ipAddress })?.macAddress
            }
            cacheMetrics[ipAddress] = cached
        }

        metricsCache.saveAll(cacheMetrics)
        #if os(iOS)
            WatchSyncManager.shared.updateCacheMetrics(cacheMetrics)
        #endif
    }

    private func loadCachedFleetHealth() -> FleetHealthCacheEntry? {
        guard !savedDevices.isEmpty,
            let data = defaults.data(forKey: StorageKeys.cachedFleetHealthSnapshot)
        else { return nil }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let entry = try decoder.decode(FleetHealthCacheEntry.self, from: data)
            guard entry.deviceIPAddresses == currentDeviceIPAddresses else { return nil }
            return entry
        } catch {
            return nil
        }
    }

    private func saveCachedFleetHealthSnapshot(_ snapshot: FleetHealthSnapshot) {
        guard !savedDevices.isEmpty else { return }

        let entry = FleetHealthCacheEntry(
            snapshot: snapshot,
            generatedAt: Date(),
            deviceIPAddresses: currentDeviceIPAddresses
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entry)
            defaults.set(data, forKey: StorageKeys.cachedFleetHealthSnapshot)
            cachedFleetHealth = entry
        } catch {
            // Best-effort cache; ignore errors
        }
    }

    private func persistHistoricalSamples(_ samples: [(deviceId: String, metrics: DeviceMetrics)]) {
        guard let modelContext, let historicalDataRetentionController, !samples.isEmpty else {
            return
        }

        let timestamp = Date()

        do {
            for sample in samples {
                let dataPoint = HistoricalDataPoint(
                    timestamp: timestamp,
                    hashrate: sample.metrics.hashrate,
                    temperature: sample.metrics.temperature,
                    deviceId: sample.deviceId
                )
                modelContext.insert(dataPoint)
            }

            try historicalDataRetentionController.savePendingChanges(
                pruningIfNeededFor: samples.map(\.deviceId)
            )
        } catch {
        }
    }

    private func parseDifficultyString(_ diffString: String) -> Double {
        let multipliers: [Character: Double] = [
            "K": 1_000,
            "M": 1_000_000,
            "G": 1_000_000_000,
            "T": 1_000_000_000_000,
            "P": 1_000_000_000_000_000,
        ]

        let trimmedString = diffString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedString.isEmpty else { return 0.0 }

        guard let lastChar = trimmedString.last else { return 0.0 }

        var numericPartString = trimmedString
        var multiplier: Double = 1.0

        if let suffix = lastChar.uppercased().first, let mult = multipliers[suffix] {
            multiplier = mult
            numericPartString = String(trimmedString.dropLast())
        } else if lastChar.isLetter {
            return 0.0
        }

        // Remove commas from numeric part before parsing
        let cleanedNumericString = numericPartString.replacing(",", with: "")
        guard let numericValue = Double(cleanedNumericString) else {
            return 0.0
        }

        // Convert the raw display value to the actual base value
        // E.g., "4,070,000 T" should become 4.07 (in millions base unit)
        return numericValue / 1_000_000.0 * multiplier
    }

    private func saveIPsAndReloadWidget() {
        let ipAddresses = savedDevices.map { $0.ipAddress }
        defaults.set(ipAddresses, forKey: "savedDeviceIPs")
        defaults.set(
            DeviceManagementService.macAddressesByIPAddress(savedDevices),
            forKey: "savedDeviceMACAddresses"
        )
        dependencies.reloadWidget()
    }

    func reorderDevices(from source: IndexSet, to destination: Int) {
        recentRelocations = [:]
        savedDevices.move(fromOffsets: source, toOffset: destination)

        do {
            try dependencies.deviceManagement.reorderDevices(savedDevices)
        } catch {
            // If reordering fails, revert the local change
            loadDevices()
        }
    }

    // MARK: - Stable miner identity

    private func recordMACAddress(_ macAddress: String, forDeviceAt index: Int) {
        savedDevices[index].macAddress = macAddress
        do {
            try dependencies.deviceManagement.recordMACAddress(
                macAddress,
                savedDevices[index].ipAddress
            )
        } catch {
            // The identity stays in memory; the next successful write persists it.
        }
    }

    /// Looks for saved miners that stopped answering at their saved address and, when
    /// a subnet scan finds their MAC address elsewhere, moves them there.
    ///
    /// Only miners whose MAC address is known can be found this way; a miner saved
    /// before identities were tracked has to answer at its saved address once first.
    private func relocateMissingDevicesIfNeeded() async {
        let missingDevices = savedDevices.filter { device in
            device.macAddress != nil && !reachableIPs.contains(device.ipAddress)
        }
        guard !missingDevices.isEmpty else { return }

        let now = Date()
        if let lastRelocationScanAt,
            now.timeIntervalSince(lastRelocationScanAt)
                < dependencies.relocationScanMinimumInterval
        {
            return
        }
        lastRelocationScanAt = now

        let discoveredDevices = await dependencies.deviceManagement.scanLocalNetwork(reachableIPs)
        let missingMACAddresses = Set(missingDevices.compactMap(\.macAddress))
        let matches = discoveredDevices.filter { discovered in
            guard let macAddress = SavedDevice.normalizedMACAddress(discovered.macAddress) else {
                return false
            }
            return missingMACAddresses.contains(macAddress)
        }
        guard !matches.isEmpty else { return }

        do {
            let relocations = try dependencies.deviceManagement.relocateDevices(matches)
            guard !relocations.isEmpty else { return }
            // Reloading applies the moves the same way as any other saved-device change,
            // including a follow-up refresh that fetches from the new addresses.
            loadDevices()
        } catch {
            // The miners stay listed as offline at their old addresses until the next scan.
        }
    }

    /// Moves in-memory metrics, reachability, and stored history along with every saved
    /// miner whose MAC address now sits under a different IP address than before.
    private func followRelocatedDevices(
        from previousDevices: [SavedDevice],
        to currentDevices: [SavedDevice]
    ) {
        let previousByMACAddress = uniqueDevicesByMACAddress(previousDevices)
        let currentByMACAddress = uniqueDevicesByMACAddress(currentDevices)
        var currentByPrevious: [String: String] = [:]
        var movedMACByPrevious: [String: String] = [:]

        for (macAddress, current) in currentByMACAddress {
            guard let previous = previousByMACAddress[macAddress],
                previous.ipAddress != current.ipAddress
            else { continue }

            currentByPrevious[previous.ipAddress] = current.ipAddress
            movedMACByPrevious[previous.ipAddress] = macAddress
        }

        recentRelocations = currentByPrevious
        guard !currentByPrevious.isEmpty else { return }

        // Every destination reads the original snapshot, including when miners swap
        // addresses or move around a cycle.
        let previousMetrics = deviceMetrics
        let changedIPAddresses = Set(currentByPrevious.keys)
            .union(currentByPrevious.values)
        deviceMetrics = previousMetrics.filter { !changedIPAddresses.contains($0.key) }
        for (previous, current) in currentByPrevious {
            deviceMetrics[current] = previousMetrics[previous]
        }
        reachableIPs.subtract(changedIPAddresses)
        computeTotals()

        enqueueHistoryRelocation(
            currentByPrevious,
            before: Date(),
            movedMACByPrevious: movedMACByPrevious
        )
    }

    private func uniqueDevicesByMACAddress(_ devices: [SavedDevice]) -> [String: SavedDevice] {
        var countByMACAddress: [String: Int] = [:]
        for device in devices {
            if let macAddress = device.macAddress {
                countByMACAddress[macAddress, default: 0] += 1
            }
        }

        var deviceByMACAddress: [String: SavedDevice] = [:]
        for device in devices {
            if let macAddress = device.macAddress, countByMACAddress[macAddress] == 1 {
                deviceByMACAddress[macAddress] = device
            }
        }
        return deviceByMACAddress
    }

    private func recoverRecordedRelocations(
        in devices: [SavedDevice],
        encodedData: Data
    ) -> [SavedDevice] {
        let records = devices.flatMap { device in
            device.relocationRecords.compactMap { record -> (String, SavedDevice.RelocationRecord)? in
                guard let macAddress = device.macAddress else { return nil }
                return (macAddress, record)
            }
        }
        guard !records.isEmpty else { return devices }

        let operationIDs = Set(records.map { $0.1.operationID })
        let orderedOperations = operationIDs.sorted { first, second in
            let firstSequence = records.first { $0.1.operationID == first }?.1.sequence ?? 0
            let secondSequence = records.first { $0.1.operationID == second }?.1.sequence ?? 0
            return firstSequence < secondSequence
        }
        var jobs = pendingHistoryRelocations()
        let completedIDs = Self.completedHistoryRelocations(in: defaults)
        var queuedIDs = Set(jobs.map(\.id))
        for operationID in orderedOperations where !queuedIDs.contains(operationID)
            && !completedIDs.contains(operationID)
        {
            let moves = records.filter { $0.1.operationID == operationID }
            let currentByPrevious = Dictionary(
                uniqueKeysWithValues: moves.map { ($0.1.previousIPAddress, $0.1.currentIPAddress) }
            )
            guard let cutoff = moves.first?.1.cutoff else { continue }
            jobs.append(
                HistoryRelocationJob(
                    id: operationID,
                    currentByPrevious: currentByPrevious,
                    cutoff: cutoff
                )
            )
            queuedIDs.insert(operationID)
        }
        storeHistoryRelocations(jobs)
        remapRecordedMetrics(records, currentDevices: devices)

        var lastAddressByMAC =
            defaults.dictionary(forKey: StorageKeys.lastHistoryRelocationAddresses)
            as? [String: String] ?? [:]
        for (macAddress, record) in records.sorted(by: { $0.1.sequence < $1.1.sequence }) {
            lastAddressByMAC[macAddress] = record.currentIPAddress
        }
        defaults.set(lastAddressByMAC, forKey: StorageKeys.lastHistoryRelocationAddresses)

        var cleanedDevices = devices
        for index in cleanedDevices.indices {
            cleanedDevices[index].relocationRecords.removeAll()
        }
        if let cleanedData = try? JSONEncoder().encode(cleanedDevices),
            defaults.data(forKey: "savedDevices") == encodedData
        {
            defaults.set(cleanedData, forKey: "savedDevices")
            scheduleHistoryRelocations()
            return cleanedDevices
        }
        scheduleHistoryRelocations()
        return devices
    }

    private func remapRecordedMetrics(
        _ records: [(String, SavedDevice.RelocationRecord)],
        currentDevices: [SavedDevice]
    ) {
        let previousCache = metricsCache.loadAll()
        let movedMACAddresses = Set(records.map(\.0))
        let firstAddressByMAC = Dictionary(
            grouping: records.sorted(by: { $0.1.sequence < $1.1.sequence }),
            by: { $0.0 }
        ).compactMapValues { $0.first?.1.previousIPAddress }
        let firstCutoffByMAC = Dictionary(
            grouping: records.sorted(by: { $0.1.sequence < $1.1.sequence }),
            by: { $0.0 }
        ).compactMapValues { $0.first?.1.cutoff }
        let vacatedAddresses = Set(records.map { $0.1.previousIPAddress })
        var currentCache: [String: CachedDeviceMetrics] = [:]

        for device in currentDevices {
            guard let macAddress = device.macAddress,
                movedMACAddresses.contains(macAddress)
            else {
                if let cached = previousCache[device.ipAddress],
                    ((device.macAddress != nil && cached.macAddress == device.macAddress)
                        || (cached.macAddress == nil
                            && !vacatedAddresses.contains(device.ipAddress)))
                {
                    currentCache[device.ipAddress] = cached
                }
                continue
            }

            let matchingCache = previousCache.first { $0.value.macAddress == macAddress }?.value
            let originalCache = firstAddressByMAC[macAddress].flatMap { previousCache[$0] }
            let originalMetrics: CachedDeviceMetrics? = {
                guard let originalCache,
                    originalCache.macAddress == nil,
                    let cutoff = firstCutoffByMAC[macAddress],
                    originalCache.lastUpdated <= cutoff
                else { return nil }
                return originalCache
            }()
            var cached = matchingCache ?? originalMetrics
            if cached == nil,
                let previousAddress = firstAddressByMAC[macAddress],
                let metrics = deviceMetrics[previousAddress]
            {
                cached = CachedDeviceMetrics(from: metrics)
            }
            cached?.macAddress = macAddress
            currentCache[device.ipAddress] = cached
        }

        metricsCache.saveAll(currentCache)
        #if os(iOS)
            WatchSyncManager.shared.updateCacheMetrics(currentCache)
        #endif
    }

    private func enqueueHistoryRelocation(
        _ currentByPrevious: [String: String],
        before cutoff: Date,
        movedMACByPrevious: [String: String]
    ) {
        // More than one window can observe the same persisted move. Track each
        // miner independently so another miner's move does not make a stale
        // window enqueue the first miner's move again.
        var lastAddressByMAC =
            defaults.dictionary(forKey: StorageKeys.lastHistoryRelocationAddresses)
            as? [String: String] ?? [:]
        let unhandledMoves = currentByPrevious.filter { previous, current in
            guard let macAddress = movedMACByPrevious[previous] else { return false }
            return lastAddressByMAC[macAddress] != current
        }
        guard !unhandledMoves.isEmpty else { return }

        var jobs = pendingHistoryRelocations()
        jobs.append(
            HistoryRelocationJob(
                id: UUID().uuidString,
                currentByPrevious: unhandledMoves,
                cutoff: cutoff
            )
        )
        storeHistoryRelocations(jobs)
        remapCachedMetrics(unhandledMoves)
        for (previous, current) in unhandledMoves {
            if let macAddress = movedMACByPrevious[previous] {
                lastAddressByMAC[macAddress] = current
            }
        }
        defaults.set(lastAddressByMAC, forKey: StorageKeys.lastHistoryRelocationAddresses)
        scheduleHistoryRelocations()
    }

    private func remapCachedMetrics(_ currentByPrevious: [String: String]) {
        let previousCache = metricsCache.loadAll()
        let changedIPAddresses = Set(currentByPrevious.keys)
            .union(currentByPrevious.values)
        var currentCache = previousCache.filter { !changedIPAddresses.contains($0.key) }
        for (previous, current) in currentByPrevious {
            currentCache[current] = previousCache[previous]
            if previousCache[previous] == nil, let metrics = deviceMetrics[current] {
                currentCache[current] = CachedDeviceMetrics(from: metrics)
            }
        }
        metricsCache.saveAll(currentCache)
        #if os(iOS)
            WatchSyncManager.shared.updateCacheMetrics(currentCache)
        #endif
    }

    private func pendingHistoryRelocations() -> [HistoryRelocationJob] {
        Self.pendingHistoryRelocations(in: defaults)
    }

    private static func pendingHistoryRelocations(in defaults: UserDefaults)
        -> [HistoryRelocationJob]
    {
        guard let data = defaults.data(forKey: StorageKeys.pendingHistoryRelocations) else {
            return []
        }
        return (try? JSONDecoder().decode([HistoryRelocationJob].self, from: data)) ?? []
    }

    private static func completedHistoryRelocations(in defaults: UserDefaults) -> Set<String> {
        Set(defaults.stringArray(forKey: StorageKeys.completedHistoryRelocations) ?? [])
    }

    private func storeHistoryRelocations(_ jobs: [HistoryRelocationJob]) {
        Self.storeHistoryRelocations(jobs, in: defaults)
    }

    private static func storeHistoryRelocations(
        _ jobs: [HistoryRelocationJob],
        in defaults: UserDefaults
    ) {
        if jobs.isEmpty {
            defaults.removeObject(forKey: StorageKeys.pendingHistoryRelocations)
        } else if let data = try? JSONEncoder().encode(jobs) {
            defaults.set(data, forKey: StorageKeys.pendingHistoryRelocations)
        }
    }

    private func scheduleHistoryRelocations() {
        guard let modelContext,
            let historicalDataRelocator,
            !pendingHistoryRelocations().isEmpty
        else { return }
        let containerID = ObjectIdentifier(modelContext.container)
        guard Self.historyRelocationTasks[containerID] == nil else { return }
        let defaults = self.defaults

        Self.historyRelocationTasks[containerID] = Task { @MainActor in
            while let job = Self.pendingHistoryRelocations(in: defaults).first {
                if Self.completedHistoryRelocations(in: defaults).contains(job.id) {
                    var remainingJobs = Self.pendingHistoryRelocations(in: defaults)
                    guard remainingJobs.first?.id == job.id else { continue }
                    remainingJobs.removeFirst()
                    Self.storeHistoryRelocations(remainingJobs, in: defaults)
                    continue
                }
                do {
                    // Each window can hold unsaved history in its own context. If
                    // any save fails, leave the job queued for a later retry.
                    let contexts = (Self.historyModelContexts[containerID] ?? [])
                        .filter { $0.value != nil }
                    Self.historyModelContexts[containerID] = contexts
                    for context in contexts {
                        try context.value?.save()
                    }
                    try await historicalDataRelocator.relocate(
                        job.currentByPrevious,
                        before: job.cutoff,
                        operationID: job.id
                    )
                } catch {
                    // Keep the job for a later retry. Its ID makes saved batches
                    // safe to replay after a partial failure or process restart.
                    break
                }

                var completedIDs = Self.completedHistoryRelocations(in: defaults)
                completedIDs.insert(job.id)
                defaults.set(completedIDs.sorted(), forKey: StorageKeys.completedHistoryRelocations)

                var remainingJobs = Self.pendingHistoryRelocations(in: defaults)
                guard remainingJobs.first?.id == job.id else { continue }
                remainingJobs.removeFirst()
                Self.storeHistoryRelocations(remainingJobs, in: defaults)
            }
            Self.historyRelocationTasks[containerID] = nil
        }
    }

    // MARK: - Fleet AI Analysis (consolidated)

    private func buildFleetSummaryFromMetrics(_ metrics: [DeviceMetrics]) -> AISummary? {
        AISummaryFormatter.fleetSummary(from: metrics)
    }

    @available(iOS 18.0, macOS 15.0, *)
    func generateFleetAISummary() async {
        guard savedDevices.count > 1 else { return }

        // Build from cached metrics (simple and immediate)
        let metrics = Array(deviceMetrics.values)
        if let summary = buildFleetSummaryFromMetrics(metrics) {
            await MainActor.run { self.fleetAISummary = summary }
            saveCachedFleetSummary(summary)
        }
    }

    // MARK: - Fleet AI summary cache (simple, app-group backed)
    private func loadCachedFleetSummary() -> AISummary? {
        // Only show cached summary when device count matches to avoid obvious mismatch
        guard savedDevices.count > 1,
            let data = defaults.data(forKey: "cachedFleetAISummaryV1")
        else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let entry = try decoder.decode(FleetSummaryCacheEntry.self, from: data)
            guard entry.deviceCount == savedDevices.count else { return nil }
            return AISummary(content: entry.content)
        } catch {
            return nil
        }
    }

    private func saveCachedFleetSummary(_ summary: AISummary) {
        let entry = FleetSummaryCacheEntry(
            content: summary.content,
            generatedAt: Date(),
            deviceCount: savedDevices.count
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entry)
            defaults.set(data, forKey: "cachedFleetAISummaryV1")
        } catch {
            // Best-effort cache; ignore errors
        }
    }

}

#if DEBUG
extension DeviceListViewModel {
    func markAggregatedStatsRefreshCompletedForPreview() {
        hasCompletedAggregatedStatsRefresh = true
    }
}
#endif
