import Combine
import SwiftUI
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

    private let defaults: UserDefaults

    init(
        defaults: UserDefaults = UserDefaults(suiteName: "group.matthewramsden.traxe") ?? .standard
    ) {
        self.defaults = defaults
        loadDevices()
        saveIPsAndReloadWidget()
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

    func deleteDevice(at offsets: IndexSet) {
        let devicesToDelete = offsets.map { savedDevices[$0] }

        for device in devicesToDelete {
            do {
                try DeviceManagementService.deleteDevice(ipAddressToDelete: device.ipAddress)
                savedDevices.removeAll { $0.id == device.id }
                saveIPsAndReloadWidget()
            } catch {
            }
        }
        Task { await updateAggregatedStats() }
    }

    func updateAggregatedStats() async {
        isLoadingAggregatedStats = true
        var currentTotalHashRate: Double = 0.0
        var currentTotalPower: Double = 0.0
        var currentBestDiff: Double = 0.0
        var currentDeviceMetrics: [String: DeviceMetrics] = [:]

        await withTaskGroup(of: (String, DeviceMetrics?).self) { group in
            for device in savedDevices {
                group.addTask {
                    do {
                        let discoveredDevice = try await DeviceManagementService.checkDevice(
                            ip: device.ipAddress
                        )

                        let parsedDifficulty = await self.parseDifficultyString(
                            discoveredDevice.bestDiff
                        )

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

            for await (ipAddress, metrics) in group {
                if let metrics = metrics {
                    currentTotalHashRate += metrics.hashrate
                    currentTotalPower += metrics.power
                    currentBestDiff = max(currentBestDiff, metrics.bestDifficulty)
                    currentDeviceMetrics[ipAddress] = metrics
                }
            }
        }

        totalHashRate = currentTotalHashRate
        totalPower = currentTotalPower
        bestOverallDiff = currentBestDiff
        deviceMetrics = currentDeviceMetrics
        isLoadingAggregatedStats = false
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
}
