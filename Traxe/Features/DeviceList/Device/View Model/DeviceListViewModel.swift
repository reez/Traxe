import Combine
import StoreKit
import SwiftUI
import TipKit
import UIKit
import WidgetKit

@MainActor
final class DeviceListViewModel: ObservableObject {
    @Published var savedDevices: [SavedDevice] = []
    @Published var totalHashRate: Double = 0.0
    @Published var totalPower: Double = 0.0
    @Published var bestOverallDiff: Double = 0.0
    @Published var isLoadingAggregatedStats = false
    @Published var deviceMetrics: [String: DeviceMetrics] = [:]
    @Published var isEditMode = false
    @Published var fleetAISummary: AISummary?
    @Published var lastDataUpdate: Date = Date()
    @Published var reachableIPs: Set<String> = []
    @Published var lastSeenWhatsNewVersion: String? = nil

    private let defaults: UserDefaults
    private var aiAnalysisService: AIAnalysisService?
    private let metricsCache = DeviceMetricsCache()

    private enum StorageKeys {
        static let lastSeenWhatsNewVersion = "lastSeenWhatsNewVersion"
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

    init(
        defaults: UserDefaults = UserDefaults(suiteName: "group.matthewramsden.traxe") ?? .standard
    ) {
        self.defaults = defaults
        if #available(iOS 18.0, macOS 15.0, *) {
            self.aiAnalysisService = AIAnalysisService()
        }
        self.lastSeenWhatsNewVersion = defaults.string(
            forKey: StorageKeys.lastSeenWhatsNewVersion
        )
        loadDevices()
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

    func loadDevices() {
        guard let data = defaults.data(forKey: "savedDevices") else {
            self.savedDevices = []
            saveIPsAndReloadWidget()
            Task { await updateAggregatedStats() }
            return
        }

        do {
            let decoder = JSONDecoder()
            self.savedDevices = try decoder.decode([SavedDevice].self, from: data)
            saveIPsAndReloadWidget()
            Task { await updateAggregatedStats() }
        } catch {
            self.savedDevices = []
            saveIPsAndReloadWidget()
            Task { await updateAggregatedStats() }
        }
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

    func requestReview() {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
        else {
            return
        }

        AppStore.requestReview(in: scene)
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

        for device in devicesToDelete {
            do {
                try DeviceManagementService.deleteDevice(ipAddressToDelete: device.ipAddress)
                savedDevices.removeAll { $0.id == device.id }
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
        // Prevent overlapping refreshes
        if isLoadingAggregatedStats { return }
        // Keep existing fleet AI summary visible during refresh

        isLoadingAggregatedStats = true

        // Capture current IPs to avoid touching actor state off the main actor
        let devicesSnapshot = savedDevices

        // Perform network fetches off the main actor, then apply results on main
        let fetchedResults: [(String, DeviceMetrics?)] = await Task.detached(
            priority: .userInitiated
        ) {
            await withTaskGroup(of: (String, DeviceMetrics?).self) { group in
                for device in devicesSnapshot {
                    group.addTask {
                        do {
                            let discoveredDevice = try await DeviceManagementService.checkDevice(
                                ip: device.ipAddress
                            )
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
                                let lastChar = trimmed.last!
                                var numeric = trimmed
                                var mult: Double = 1.0
                                if let m = multipliers[lastChar.uppercased().first!] {
                                    mult = m
                                    numeric = String(trimmed.dropLast())
                                } else if lastChar.isLetter {
                                    return 0.0
                                }
                                let cleaned = numeric.replacingOccurrences(of: ",", with: "")
                                guard let value = Double(cleaned) else { return 0.0 }
                                return value / 1_000_000.0 * mult
                            }()

                            let metrics = DeviceMetrics(
                                hashrate: discoveredDevice.hashrate,
                                temperature: discoveredDevice.temperature,
                                power: discoveredDevice.power,
                                bestDifficulty: parsedDifficulty,
                                poolURL: discoveredDevice.poolURL,
                                hostname: discoveredDevice.name
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
        for (ipAddress, metrics) in fetchedResults {
            guard activeIPs.contains(ipAddress) else { continue }

            if let metrics = metrics {
                deviceMetrics[ipAddress] = metrics
                newReachables.insert(ipAddress)
                successfulFetchCount += 1
            }
        }
        // Atomically update reachable set to avoid mid-refresh greying
        reachableIPs = newReachables
        computeTotals()

        isLoadingAggregatedStats = false

        // Save all current metrics to cache
        saveCacheFromCurrentMetrics()
        // No need to regenerate summary here; computeTotals() already keeps it in sync

        if successfulFetchCount > 0 {
            WidgetCenter.shared.reloadTimelines(ofKind: "TraxeWidget")
        }
    }

    private func saveCacheFromCurrentMetrics() {
        var cacheMetrics: [String: CachedDeviceMetrics] = [:]

        for (ipAddress, metrics) in deviceMetrics {
            cacheMetrics[ipAddress] = CachedDeviceMetrics(from: metrics)
        }

        metricsCache.saveAll(cacheMetrics)
        #if os(iOS)
            WatchSyncManager.shared.updateCacheMetrics(cacheMetrics)
        #endif
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

        let lastChar = trimmedString.last!

        var numericPartString = trimmedString
        var multiplier: Double = 1.0

        if let mult = multipliers[lastChar.uppercased().first!] {
            multiplier = mult
            numericPartString = String(trimmedString.dropLast())
        } else if lastChar.isLetter {
            return 0.0
        }

        // Remove commas from numeric part before parsing
        let cleanedNumericString = numericPartString.replacingOccurrences(of: ",", with: "")
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
        WidgetCenter.shared.reloadTimelines(ofKind: "TraxeWidget")
    }

    func reorderDevices(from source: IndexSet, to destination: Int) {
        savedDevices.move(fromOffsets: source, toOffset: destination)

        do {
            try DeviceManagementService.reorderDevices(savedDevices)
        } catch {
            // If reordering fails, revert the local change
            loadDevices()
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
