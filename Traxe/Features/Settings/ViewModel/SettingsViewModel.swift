import Foundation
import Observation
import SwiftData
import SwiftUI
import WidgetKit

@Observable
@MainActor
final class SettingsViewModel {
    var bitaxeIPAddress: String = ""
    var tempAlertThreshold: Double = 85.0
    var hashrateAlertThreshold: Double = 400.0
    var currentVersion: String = "Unknown"
    var showingResetConfirmation: Bool = false
    var fanSpeed: Int = 0
    var isAutoFan: Bool = true
    var isUpdatingFan: Bool = false
    var minimumFanSpeed: Int? = nil
    var isConnected: Bool = false
    var stratumUser: String = ""
    var stratumURL: String = ""
    var stratumPortString: String = ""
    var fallbackStratumUser: String = ""
    var fallbackStratumURL: String = ""
    var fallbackStratumPortString: String = ""
    var poolBalance: Int = 50
    var isDualPool: Bool = false
    var poolMode: Int = 0
    var isUpdatingPoolConfiguration: Bool = false
    var poolConfigurationError: String? = nil
    var hostname: String = ""
    var isUpdatingHostname: Bool = false
    var hostnameConfigurationError: String? = nil

    private let userDefaults: UserDefaults
    private let sharedUserDefaults: UserDefaults
    private let networkService: NetworkService
    private let modelContext: ModelContext

    static let sharedUserDefaultsSuiteName = "group.matthewramsden.traxe"

    init(
        userDefaults: UserDefaults = .standard,
        sharedUserDefaults: UserDefaults? = nil,
        networkService: NetworkService = NetworkService(),
        modelContext: ModelContext
    ) {
        self.userDefaults = userDefaults
        if let providedSharedUserDefaults = sharedUserDefaults {
            self.sharedUserDefaults = providedSharedUserDefaults
        } else {
            self.sharedUserDefaults =
                UserDefaults(suiteName: SettingsViewModel.sharedUserDefaultsSuiteName) ?? .standard
        }
        self.networkService = networkService
        self.modelContext = modelContext
        loadSettings()
    }

    func loadSettings() {
        bitaxeIPAddress = sharedUserDefaults.string(forKey: "bitaxeIPAddress") ?? ""

        tempAlertThreshold = userDefaults.double(forKey: "tempAlertThreshold")
        if tempAlertThreshold == 0 { tempAlertThreshold = 85.0 }

        hashrateAlertThreshold = userDefaults.double(forKey: "hashrateAlertThreshold")
        if hashrateAlertThreshold == 0 { hashrateAlertThreshold = 400.0 }

        Task {
            await fetchDeviceSettings()
        }
    }

    func saveSettings() {
        let trimmedIP = bitaxeIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIP.isEmpty else {
            return
        }

        sharedUserDefaults.set(trimmedIP, forKey: "bitaxeIPAddress")

        userDefaults.set(tempAlertThreshold, forKey: "tempAlertThreshold")
        userDefaults.set(hashrateAlertThreshold, forKey: "hashrateAlertThreshold")

        WidgetCenter.shared.reloadTimelines(ofKind: "TraxeWidget")
    }

    func restartDevice() async {
        do {
            try await networkService.restartDevice()
        } catch {
            return
        }
    }

    func fetchDeviceSettings() async {
        do {
            let systemInfo = try await networkService.fetchSystemInfo()
            currentVersion = systemInfo.version
            fanSpeed = systemInfo.fanspeed ?? 0
            isAutoFan = systemInfo.autofanspeed != 0
            minimumFanSpeed = systemInfo.minimumFanSpeed
            stratumUser = systemInfo.stratumUser
            stratumURL = systemInfo.stratumURL
            stratumPortString = String(systemInfo.stratumPort)
            fallbackStratumUser = systemInfo.fallbackStratumUser ?? ""
            fallbackStratumURL = systemInfo.fallbackStratumURL ?? ""
            fallbackStratumPortString = systemInfo.fallbackStratumPort.map { String($0) } ?? ""
            poolBalance = max(0, min(100, systemInfo.stratum?.poolBalance ?? 50))
            let detectedPoolMode =
                systemInfo.stratum?.poolMode ?? systemInfo.stratum?.activePoolMode ?? 0
            poolMode = detectedPoolMode == 1 ? 1 : 0
            isDualPool = poolMode == 1
            hostname = systemInfo.hostname
            isConnected = true
        } catch {
            currentVersion = "Unknown"
            isConnected = false
        }
    }

    func toggleAutoFan() async {
        isUpdatingFan = true
        do {
            try await networkService.updateSystemSettings(autofanspeed: isAutoFan ? 0 : 1)
            isAutoFan.toggle()
        } catch {
        }
        isUpdatingFan = false
    }

    func adjustFanSpeed(by amount: Int) async {
        guard !isAutoFan else { return }
        isUpdatingFan = true
        let newSpeed = max(0, min(100, fanSpeed + amount))
        do {
            try await networkService.updateSystemSettings(manualFanSpeed: newSpeed)
            fanSpeed = newSpeed
        } catch {
        }
        isUpdatingFan = false
    }

    func savePoolConfiguration() async -> Bool {
        isUpdatingPoolConfiguration = true
        poolConfigurationError = nil
        var success = false
        let targetPoolBalance = poolMode == 1 ? max(1, min(99, poolBalance)) : nil

        var portToSave: Int? = nil
        if let port = Int(stratumPortString), !stratumPortString.isEmpty {
            portToSave = port
        } else if !stratumPortString.isEmpty {
            poolConfigurationError = "Invalid port number. Please enter a valid number."
            isUpdatingPoolConfiguration = false
            return false
        }

        var fallbackPortToSave: Int? = nil
        if let port = Int(fallbackStratumPortString), !fallbackStratumPortString.isEmpty {
            fallbackPortToSave = port
        } else if !fallbackStratumPortString.isEmpty {
            poolConfigurationError = "Invalid fallback port number. Please enter a valid number."
            isUpdatingPoolConfiguration = false
            return false
        }

        do {
            try await networkService.updateSystemSettings(
                stratumUser: stratumUser.isEmpty ? nil : stratumUser,
                stratumURL: stratumURL.isEmpty ? nil : stratumURL,
                stratumPort: portToSave,
                fallbackStratumUser: fallbackStratumUser.isEmpty ? nil : fallbackStratumUser,
                fallbackStratumURL: fallbackStratumURL.isEmpty ? nil : fallbackStratumURL,
                fallbackStratumPort: fallbackPortToSave,
                poolBalance: targetPoolBalance,
                poolMode: poolMode
            )

            let systemInfo = try await networkService.fetchSystemInfo()
            let activePoolMode = systemInfo.stratum?.activePoolMode ?? 0
            if activePoolMode != poolMode {
                try await networkService.restartDevice()
                let deadline = Date().addingTimeInterval(30)
                var didActivatePoolMode = false
                while Date() < deadline {
                    if let updatedInfo = try? await networkService.fetchSystemInfo(),
                        (updatedInfo.stratum?.activePoolMode ?? 0) == poolMode
                    {
                        didActivatePoolMode = true
                        break
                    }
                    try? await Task.sleep(for: .seconds(2))
                }

                if didActivatePoolMode {
                    if poolMode == 1, let targetPoolBalance {
                        try await networkService.updateSystemSettings(
                            poolBalance: targetPoolBalance
                        )
                    }
                } else {
                    poolConfigurationError =
                        "Pool mode requires a restart before applying changes. Please try again."
                    isUpdatingPoolConfiguration = false
                    return false
                }
            }

            await fetchDeviceSettings()
            success = true
        } catch let error {
            poolConfigurationError =
                "Failed to save pool configuration: \(error.localizedDescription)"
            success = false
        }
        isUpdatingPoolConfiguration = false
        return success
    }

    func saveHostnameConfiguration() async -> Bool {
        isUpdatingHostname = true
        hostnameConfigurationError = nil
        var success = false

        do {
            try await networkService.updateSystemSettings(
                hostname: hostname.isEmpty ? nil : hostname
            )
            await fetchDeviceSettings()
            success = true
        } catch let error {
            hostnameConfigurationError =
                "Failed to save hostname: \(error.localizedDescription)"
            success = false
        }
        isUpdatingHostname = false
        return success
    }

}
