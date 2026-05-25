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
    var supportsStratumProtocolSettings: Bool = false
    var stratumProtocol: String = ""
    var fallbackStratumProtocol: String = ""
    var stratumV2ChannelType: String = ""
    var fallbackStratumV2ChannelType: String = ""
    var stratumV2AuthorityPubkey: String = ""
    var fallbackStratumV2AuthorityPubkey: String = ""
    var poolBalance: Int = 50
    var isDualPool: Bool = false
    var poolMode: Int = 0
    var isUpdatingPoolConfiguration: Bool = false
    var poolConfigurationError: String? = nil
    var hostname: String = ""
    var isUpdatingHostname: Bool = false
    var hostnameConfigurationError: String? = nil
    var deleteMinerErrorMessage: String? = nil

    var canDeleteCurrentMiner: Bool {
        !deleteMinerIPAddress.isEmpty
    }

    private let userDefaults: UserDefaults
    private let sharedUserDefaults: UserDefaults
    private let networkService: NetworkService
    private let modelContext: ModelContext
    private let shouldFetchDeviceSettingsOnLoad: Bool
    private let deleteDevice: (_ ipAddressToDelete: String) throws -> Void
    private var selectedMinerIPAddress: String = ""

    static let sharedUserDefaultsSuiteName = "group.matthewramsden.traxe"

    init(
        userDefaults: UserDefaults = .standard,
        sharedUserDefaults: UserDefaults? = nil,
        networkService: NetworkService = NetworkService(),
        modelContext: ModelContext,
        shouldFetchDeviceSettingsOnLoad: Bool = true,
        deleteDevice: @escaping (_ ipAddressToDelete: String) throws -> Void = {
            ipAddressToDelete in
            try DeviceManagementService.deleteDevice(ipAddressToDelete: ipAddressToDelete)
        }
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
        self.shouldFetchDeviceSettingsOnLoad = shouldFetchDeviceSettingsOnLoad
        self.deleteDevice = deleteDevice
        loadSettings()
    }

    func loadSettings() {
        let storedIPAddress = sharedUserDefaults.string(forKey: "bitaxeIPAddress") ?? ""
        bitaxeIPAddress = storedIPAddress
        selectedMinerIPAddress = storedIPAddress

        tempAlertThreshold = userDefaults.double(forKey: "tempAlertThreshold")
        if tempAlertThreshold == 0 { tempAlertThreshold = 85.0 }

        hashrateAlertThreshold = userDefaults.double(forKey: "hashrateAlertThreshold")
        if hashrateAlertThreshold == 0 { hashrateAlertThreshold = 400.0 }

        if shouldFetchDeviceSettingsOnLoad {
            Task {
                await fetchDeviceSettings()
            }
        }
    }

    func saveSettings() {
        let trimmedIP = bitaxeIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIP.isEmpty else {
            return
        }

        sharedUserDefaults.set(trimmedIP, forKey: "bitaxeIPAddress")
        selectedMinerIPAddress = trimmedIP

        userDefaults.set(tempAlertThreshold, forKey: "tempAlertThreshold")
        userDefaults.set(hashrateAlertThreshold, forKey: "hashrateAlertThreshold")

        WidgetCenter.shared.reloadTimelines(ofKind: "TraxeWidget")
    }

    func deleteCurrentMiner() -> String? {
        let ipAddressToDelete = deleteMinerIPAddress
        guard !ipAddressToDelete.isEmpty else {
            deleteMinerErrorMessage = "No miner is selected."
            return nil
        }

        do {
            try deleteDevice(ipAddressToDelete)
            sharedUserDefaults.removeObject(forKey: "bitaxeIPAddress")
            bitaxeIPAddress = ""
            selectedMinerIPAddress = ""
            currentVersion = "Unknown"
            isConnected = false
            deleteMinerErrorMessage = nil
            resetStratumProtocolDetails()
            return ipAddressToDelete
        } catch {
            deleteMinerErrorMessage = "Failed to delete miner: \(error.localizedDescription)"
            return nil
        }
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
            supportsStratumProtocolSettings = systemInfo.supportsStratumProtocolSettings
            stratumProtocol = systemInfo.stratumProtocol ?? ""
            fallbackStratumProtocol = systemInfo.fallbackStratumProtocol ?? ""
            stratumV2ChannelType = systemInfo.stratumV2ChannelType ?? ""
            fallbackStratumV2ChannelType = systemInfo.fallbackStratumV2ChannelType ?? ""
            stratumV2AuthorityPubkey = systemInfo.stratumV2AuthorityPubkey ?? ""
            fallbackStratumV2AuthorityPubkey = systemInfo.fallbackStratumV2AuthorityPubkey ?? ""
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
            resetStratumProtocolDetails()
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

        var stratumProtocolToSave: String? = nil
        var fallbackStratumProtocolToSave: String? = nil
        var stratumV2ChannelTypeToSave: String? = nil
        var fallbackStratumV2ChannelTypeToSave: String? = nil
        var stratumV2AuthorityPubkeyToSave: String? = nil
        var fallbackStratumV2AuthorityPubkeyToSave: String? = nil

        if supportsStratumProtocolSettings {
            if let validationError = StratumProtocolSettingsValidator.validationError(
                protocolValue: stratumProtocol,
                channelType: stratumV2ChannelType,
                authorityPubkey: stratumV2AuthorityPubkey,
                poolName: "Primary SV2"
            ) {
                poolConfigurationError = validationError
                isUpdatingPoolConfiguration = false
                return false
            }

            if let validationError = StratumProtocolSettingsValidator.validationError(
                protocolValue: fallbackStratumProtocol,
                channelType: fallbackStratumV2ChannelType,
                authorityPubkey: fallbackStratumV2AuthorityPubkey,
                poolName: "Fallback SV2"
            ) {
                poolConfigurationError = validationError
                isUpdatingPoolConfiguration = false
                return false
            }

            stratumProtocolToSave = StratumProtocolSettingsValidator.protocolValueToSave(
                stratumProtocol
            )
            fallbackStratumProtocolToSave = StratumProtocolSettingsValidator.protocolValueToSave(
                fallbackStratumProtocol
            )
            stratumV2ChannelTypeToSave = StratumProtocolSettingsValidator.channelTypeToSave(
                stratumV2ChannelType
            )
            fallbackStratumV2ChannelTypeToSave = StratumProtocolSettingsValidator.channelTypeToSave(
                fallbackStratumV2ChannelType
            )
            stratumV2AuthorityPubkeyToSave = StratumProtocolSettingsValidator
                .trimmedAuthorityPubkey(stratumV2AuthorityPubkey)
            fallbackStratumV2AuthorityPubkeyToSave = StratumProtocolSettingsValidator
                .trimmedAuthorityPubkey(fallbackStratumV2AuthorityPubkey)
        }

        do {
            try await networkService.updateSystemSettings(
                stratumUser: stratumUser.isEmpty ? nil : stratumUser,
                stratumURL: stratumURL.isEmpty ? nil : stratumURL,
                stratumPort: portToSave,
                fallbackStratumUser: fallbackStratumUser.isEmpty ? nil : fallbackStratumUser,
                fallbackStratumURL: fallbackStratumURL.isEmpty ? nil : fallbackStratumURL,
                fallbackStratumPort: fallbackPortToSave,
                stratumProtocol: stratumProtocolToSave,
                fallbackStratumProtocol: fallbackStratumProtocolToSave,
                stratumV2ChannelType: stratumV2ChannelTypeToSave,
                fallbackStratumV2ChannelType: fallbackStratumV2ChannelTypeToSave,
                stratumV2AuthorityPubkey: stratumV2AuthorityPubkeyToSave,
                fallbackStratumV2AuthorityPubkey: fallbackStratumV2AuthorityPubkeyToSave,
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

    private var trimmedMinerIPAddress: String {
        bitaxeIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var deleteMinerIPAddress: String {
        let trimmedSelectedIPAddress = selectedMinerIPAddress.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard trimmedSelectedIPAddress.isEmpty else { return trimmedSelectedIPAddress }
        return trimmedMinerIPAddress
    }

    private func resetStratumProtocolDetails() {
        supportsStratumProtocolSettings = false
        stratumProtocol = ""
        fallbackStratumProtocol = ""
        stratumV2ChannelType = ""
        fallbackStratumV2ChannelType = ""
        stratumV2AuthorityPubkey = ""
        fallbackStratumV2AuthorityPubkey = ""
    }

}
