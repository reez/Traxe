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
    var supportsActivePoolSelection: Bool = false
    var useFallbackStratum: Bool = false
    // ESP-Miner v2.15 pool slots. `poolCatalog` is the miner's current list; Pool Settings
    // edits a copy and hands it back through `savePoolCatalog`.
    var supportsMultiPoolSettings: Bool = false
    var poolCatalog: PoolCatalogDraft? = nil
    var supportsPoolModeSettings: Bool = false
    var poolBalance: Int = 50
    var isDualPool: Bool = false
    var poolMode: Int = 0
    var isUpdatingPoolConfiguration: Bool = false
    var poolConfigurationError: String? = nil
    var hostname: String = ""
    var isUpdatingHostname: Bool = false
    var hostnameConfigurationError: String? = nil
    private(set) var isSettingsConfigurationEditable: Bool = false
    private(set) var settingsConfigurationMessage: String? = nil
    var deleteMinerErrorMessage: String? = nil
    /// Set by a successful pool or hostname save that the miner only applies while booting.
    /// ESP-Miner before 2.15 keeps the flat pool settings in NVS and reads them at startup, and
    /// ESP-Miner and NerdQAxe both read a saved hostname only while Wi-Fi and mDNS start, so
    /// the miner keeps its old configuration until it restarts; both web UIs warn the same way
    /// after a save. NerdQAxe reconnects to a changed pool on its own and the ESP-Miner 2.15
    /// pool catalog restarts when needed, so neither sets this for a pool save. The settings
    /// screens present their restart alert from it and clear it when the alert closes.
    var needsRestartToApplySettings: Bool = false

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
    /// The hostname the miner last reported, so a save can tell a rename from a no-op.
    private var reportedHostname: String = ""

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
            supportsPoolModeSettings = false
            supportsActivePoolSelection = false
            supportsMultiPoolSettings = false
            poolCatalog = nil
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
            applySettings(from: systemInfo)
        } catch {
            if let telemetry = try? await networkService.fetchMinerTelemetry() {
                currentVersion = telemetry.version
                fanSpeed = telemetry.fanspeed ?? 0
                hostname = telemetry.hostname
                reportedHostname = telemetry.hostname
                isConnected = true
                isSettingsConfigurationEditable = false
                settingsConfigurationMessage = Self.settingsConfigurationUnavailableMessage
                supportsPoolModeSettings = false
                supportsActivePoolSelection = false
                supportsMultiPoolSettings = false
                poolCatalog = nil
                resetStratumProtocolDetails()
            } else {
                currentVersion = "Unknown"
                isConnected = false
                isSettingsConfigurationEditable = false
                settingsConfigurationMessage = nil
                supportsPoolModeSettings = false
                supportsActivePoolSelection = false
                supportsMultiPoolSettings = false
                poolCatalog = nil
                resetStratumProtocolDetails()
            }
        }
    }

    private func applySettings(from systemInfo: SystemInfoDTO) {
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
        supportsActivePoolSelection = systemInfo.supportsActivePoolSelection
        useFallbackStratum = systemInfo.useFallbackStratum ?? false
        supportsMultiPoolSettings = systemInfo.supportsMultiPoolSettings
        poolCatalog =
            systemInfo.supportsMultiPoolSettings ? PoolCatalogDraft(systemInfo: systemInfo) : nil
        supportsPoolModeSettings = systemInfo.supportsPoolModeSettings
        poolBalance = max(0, min(100, systemInfo.stratum?.poolBalance ?? 50))
        let detectedPoolMode =
            systemInfo.stratum?.poolMode ?? systemInfo.stratum?.activePoolMode ?? 0
        poolMode = detectedPoolMode == 1 ? 1 : 0
        isDualPool = poolMode == 1
        hostname = systemInfo.hostname
        reportedHostname = systemInfo.hostname
        isConnected = true
        isSettingsConfigurationEditable = true
        settingsConfigurationMessage = nil
    }

    func toggleAutoFan() async {
        guard isSettingsConfigurationEditable else { return }
        isUpdatingFan = true
        do {
            try await networkService.updateSystemSettings(autofanspeed: isAutoFan ? 0 : 1)
            isAutoFan.toggle()
        } catch {
        }
        isUpdatingFan = false
    }

    func adjustFanSpeed(by amount: Int) async {
        guard !isAutoFan, isSettingsConfigurationEditable else { return }
        isUpdatingFan = true
        let newSpeed = max(0, min(100, fanSpeed + amount))
        do {
            // ESP-Miner 2.11 and later read the manual speed from `manualFanSpeed`; 2.10 and
            // earlier only read `fanspeed`. Each ignores the key it does not know and answers
            // 200 either way, so both are sent.
            try await networkService.updateSystemSettings(
                fanspeed: newSpeed,
                manualFanSpeed: newSpeed
            )
            fanSpeed = newSpeed
        } catch {
        }
        isUpdatingFan = false
    }

    func savePoolConfiguration() async -> Bool {
        guard isSettingsConfigurationEditable else {
            poolConfigurationError = Self.settingsConfigurationUnavailableMessage
            return false
        }

        isUpdatingPoolConfiguration = true
        poolConfigurationError = nil
        needsRestartToApplySettings = false
        var success = false
        let targetPoolBalance =
            supportsPoolModeSettings && poolMode == 1 ? max(1, min(99, poolBalance)) : nil

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
            let currentSystemInfo = try await networkService.fetchSystemInfo()

            if currentSystemInfo.supportsMultiPoolSettings {
                let poolEdits = [
                    PoolSettingsEdit(
                        id: currentSystemInfo.primaryPoolID,
                        stratumURL: stratumURL.isEmpty ? nil : stratumURL,
                        stratumPort: portToSave,
                        stratumUser: stratumUser.isEmpty ? nil : stratumUser,
                        stratumProtocol: stratumProtocolToSave,
                        stratumV2ChannelType: stratumV2ChannelTypeToSave,
                        stratumV2AuthorityPubkey: stratumV2AuthorityPubkeyToSave
                    ),
                    PoolSettingsEdit(
                        id: currentSystemInfo.secondaryPoolID,
                        stratumURL: fallbackStratumURL.isEmpty ? nil : fallbackStratumURL,
                        stratumPort: fallbackPortToSave,
                        stratumUser: fallbackStratumUser.isEmpty ? nil : fallbackStratumUser,
                        stratumProtocol: fallbackStratumProtocolToSave,
                        stratumV2ChannelType: fallbackStratumV2ChannelTypeToSave,
                        stratumV2AuthorityPubkey: fallbackStratumV2AuthorityPubkeyToSave
                    ),
                ]
                // Pool indices are left out of the body so the miner keeps its current values;
                // this screen does not edit them. `useFallbackStratum` is only sent when the
                // user picked a different active pool.
                let poolsToSave = MultiPoolSettingsPlan.pools(
                    for: poolEdits,
                    from: currentSystemInfo
                )
                let useFallbackStratumToSave: Bool? =
                    supportsActivePoolSelection
                        && currentSystemInfo.supportsActivePoolSelection
                        && currentSystemInfo.useFallbackStratum != useFallbackStratum
                    ? useFallbackStratum : nil

                // "Fallback" needs a fallback pool the miner already has, or a complete new
                // slot in this save; otherwise the miner would boot onto an empty slot.
                let secondaryPoolID = currentSystemInfo.secondaryPoolID
                if useFallbackStratumToSave == true,
                    currentSystemInfo.pool(withID: secondaryPoolID) == nil,
                    !poolsToSave.contains(where: { $0.id == secondaryPoolID })
                {
                    poolConfigurationError = Self.fallbackPoolRequiredMessage
                    isUpdatingPoolConfiguration = false
                    return false
                }

                if !poolsToSave.isEmpty {
                    try await networkService.updatePoolSettings(pools: poolsToSave)
                }

                // v2.15 answers with HTTP success even when it ignored the submitted values,
                // so the saved values have to be read back before reporting success.
                let savedSystemInfo = try await networkService.fetchSystemInfo()
                let unsavedPoolIDs = MultiPoolSettingsPlan.unsavedPoolIDs(
                    for: poolEdits,
                    in: savedSystemInfo
                )
                guard unsavedPoolIDs.isEmpty else {
                    applySettings(from: savedSystemInfo)
                    isUpdatingPoolConfiguration = false
                    poolConfigurationError = Self.poolSettingsNotAppliedMessage
                    return false
                }
                guard let useFallbackStratumToSave else {
                    applySettings(from: savedSystemInfo)
                    isUpdatingPoolConfiguration = false
                    return true
                }

                // Only now persist the active pool, in its own PATCH: the firmware stores
                // scalar keys before it gets to the pools array, so sending it together with
                // the pools would leave it behind in NVS whenever the pool change did not apply.
                try await networkService.updatePoolSettings(
                    pools: [],
                    useFallbackStratum: useFallbackStratumToSave
                )

                // The miner reads `useFallbackStratum` only while booting, so the new active
                // pool takes effect, and shows up in system info, once it restarted.
                do {
                    try await networkService.restartDevice()
                } catch {
                    applySettings(from: savedSystemInfo)
                    isUpdatingPoolConfiguration = false
                    poolConfigurationError = Self.activePoolRestartFailedMessage
                    return false
                }
                let deadline = Date().addingTimeInterval(45)
                var restartedSystemInfo: SystemInfoDTO? = nil
                while Date() < deadline {
                    if let updatedInfo = try? await networkService.fetchSystemInfo(),
                        updatedInfo.useFallbackStratum == useFallbackStratumToSave
                    {
                        restartedSystemInfo = updatedInfo
                        break
                    }
                    try? await Task.sleep(for: .seconds(2))
                }
                isUpdatingPoolConfiguration = false

                guard let restartedSystemInfo else {
                    applySettings(from: savedSystemInfo)
                    poolConfigurationError = Self.activePoolNotAppliedMessage
                    return false
                }
                applySettings(from: restartedSystemInfo)
                return true
            }

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
                poolMode: supportsPoolModeSettings ? poolMode : nil
            )
            // ESP-Miner before 2.15 keeps these flat settings in NVS and reads them while
            // booting, so a changed pool only takes effect after a restart. NerdQAxe, which
            // reports `stratum.poolMode`, reconnects on its own after a save.
            needsRestartToApplySettings =
                !currentSystemInfo.supportsPoolModeSettings
                && Self.flatPoolSettingsDiffer(
                    from: currentSystemInfo,
                    stratumURL: stratumURL.isEmpty ? nil : stratumURL,
                    stratumPort: portToSave,
                    stratumUser: stratumUser.isEmpty ? nil : stratumUser,
                    fallbackStratumURL: fallbackStratumURL.isEmpty ? nil : fallbackStratumURL,
                    fallbackStratumPort: fallbackPortToSave,
                    fallbackStratumUser: fallbackStratumUser.isEmpty ? nil : fallbackStratumUser,
                    stratumProtocol: stratumProtocolToSave,
                    fallbackStratumProtocol: fallbackStratumProtocolToSave,
                    stratumV2ChannelType: stratumV2ChannelTypeToSave,
                    fallbackStratumV2ChannelType: fallbackStratumV2ChannelTypeToSave,
                    stratumV2AuthorityPubkey: stratumV2AuthorityPubkeyToSave,
                    fallbackStratumV2AuthorityPubkey: fallbackStratumV2AuthorityPubkeyToSave
                )

            if supportsPoolModeSettings {
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

    // Applies a Pool Settings draft to an ESP-Miner v2.15 miner: changed slots first, then the
    // primary/fallback selection and active pool, then cleared slots, then a restart when the
    // pools the miner mines on changed. Every step is read back because v2.15 answers with
    // HTTP success even when it ignored the submitted values.
    func savePoolCatalog(_ draft: PoolCatalogDraft) async -> Bool {
        guard isSettingsConfigurationEditable else {
            poolConfigurationError = Self.settingsConfigurationUnavailableMessage
            return false
        }
        if let validationError = PoolCatalogSavePlan.validationError(for: draft) {
            poolConfigurationError = validationError
            return false
        }

        isUpdatingPoolConfiguration = true
        poolConfigurationError = nil
        needsRestartToApplySettings = false

        do {
            let currentSystemInfo = try await networkService.fetchSystemInfo()
            guard currentSystemInfo.supportsMultiPoolSettings else {
                applySettings(from: currentSystemInfo)
                isUpdatingPoolConfiguration = false
                poolConfigurationError = Self.poolCatalogUnsupportedMessage
                return false
            }

            let poolsToSave = PoolCatalogSavePlan.poolsToSave(for: draft, from: currentSystemInfo)
            let selectionChange = PoolCatalogSavePlan.selectionChange(
                for: draft,
                from: currentSystemInfo
            )
            let poolIDsToDelete = PoolCatalogSavePlan.poolIDsToDelete(
                for: draft,
                from: currentSystemInfo
            )

            if poolsToSave.isEmpty, selectionChange.isEmpty, poolIDsToDelete.isEmpty {
                applySettings(from: currentSystemInfo)
                isUpdatingPoolConfiguration = false
                return true
            }

            // Pool slots go first, on their own, and are read back before anything points at
            // them.
            var latestSystemInfo = currentSystemInfo
            if !poolsToSave.isEmpty {
                try await networkService.updatePoolSettings(pools: poolsToSave)
                latestSystemInfo = try await networkService.fetchSystemInfo()
                let unsavedPoolIDs = MultiPoolSettingsPlan.unsavedPoolIDs(
                    for: PoolCatalogSavePlan.settingsEdits(for: draft),
                    in: latestSystemInfo
                )
                guard unsavedPoolIDs.isEmpty else {
                    applySettings(from: latestSystemInfo)
                    isUpdatingPoolConfiguration = false
                    poolConfigurationError = Self.poolSettingsNotAppliedMessage
                    return false
                }
            }

            // Only now move the selection: the firmware stores these scalar keys even when it
            // drops a pool object from the same body, which could point it at an empty slot.
            if !selectionChange.isEmpty {
                try await networkService.updatePoolSettings(
                    pools: [],
                    primaryPoolIndex: selectionChange.primaryPoolIndex,
                    secondaryPoolIndex: selectionChange.secondaryPoolIndex,
                    useFallbackStratum: selectionChange.useFallbackStratum
                )
            }

            // Cleared after the selection moved off them; the firmware refuses to clear a
            // selected slot.
            for poolID in poolIDsToDelete {
                try await networkService.deletePool(id: poolID)
            }

            let requiresRestart = PoolCatalogSavePlan.requiresRestart(
                for: draft,
                poolsToSave: poolsToSave,
                selectionChange: selectionChange
            )
            guard requiresRestart else {
                if !poolIDsToDelete.isEmpty {
                    latestSystemInfo = try await networkService.fetchSystemInfo()
                }
                applySettings(from: latestSystemInfo)
                isUpdatingPoolConfiguration = false
                guard PoolCatalogSavePlan.isApplied(draft, in: latestSystemInfo) else {
                    poolConfigurationError = Self.poolSettingsNotAppliedMessage
                    return false
                }
                return true
            }

            // The pool selection and active pool are read while booting, so the change takes
            // effect, and shows up in system info, once the miner restarted.
            do {
                try await networkService.restartDevice()
            } catch {
                applySettings(from: latestSystemInfo)
                isUpdatingPoolConfiguration = false
                poolConfigurationError = Self.poolCatalogRestartFailedMessage
                return false
            }
            let deadline = Date().addingTimeInterval(45)
            var restartedSystemInfo: SystemInfoDTO? = nil
            while Date() < deadline {
                if let updatedInfo = try? await networkService.fetchSystemInfo(),
                    PoolCatalogSavePlan.isApplied(draft, in: updatedInfo)
                {
                    restartedSystemInfo = updatedInfo
                    break
                }
                try? await Task.sleep(for: .seconds(2))
            }
            isUpdatingPoolConfiguration = false

            guard let restartedSystemInfo else {
                applySettings(from: latestSystemInfo)
                poolConfigurationError = Self.poolCatalogRestartNotConfirmedMessage
                return false
            }
            applySettings(from: restartedSystemInfo)
            return true
        } catch let error {
            isUpdatingPoolConfiguration = false
            poolConfigurationError =
                "Failed to save pool configuration: \(error.localizedDescription)"
            return false
        }
    }

    func saveHostnameConfiguration() async -> Bool {
        guard isSettingsConfigurationEditable else {
            hostnameConfigurationError = Self.settingsConfigurationUnavailableMessage
            return false
        }

        isUpdatingHostname = true
        hostnameConfigurationError = nil
        needsRestartToApplySettings = false
        var success = false

        do {
            let hostnameToSave = hostname.isEmpty ? nil : hostname
            try await networkService.updateSystemSettings(hostname: hostnameToSave)
            // ESP-Miner and NerdQAxe both store the hostname and read it while Wi-Fi and mDNS
            // start, and each web UI asks for a restart after changing it.
            needsRestartToApplySettings =
                hostnameToSave != nil && hostnameToSave != reportedHostname
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

    /// Whether any value in a flat pool PATCH differs from what the miner last reported.
    /// Values the request leaves out are not compared, and a reported `nil` counts as empty,
    /// so saving unchanged settings does not ask for a restart while a real change always does.
    private static func flatPoolSettingsDiffer(
        from systemInfo: SystemInfoDTO,
        stratumURL: String?,
        stratumPort: Int?,
        stratumUser: String?,
        fallbackStratumURL: String?,
        fallbackStratumPort: Int?,
        fallbackStratumUser: String?,
        stratumProtocol: String?,
        fallbackStratumProtocol: String?,
        stratumV2ChannelType: String?,
        fallbackStratumV2ChannelType: String?,
        stratumV2AuthorityPubkey: String?,
        fallbackStratumV2AuthorityPubkey: String?
    ) -> Bool {
        let values: [(sent: String?, reported: String?)] = [
            (stratumURL, systemInfo.stratumURL),
            (stratumPort.map { String($0) }, String(systemInfo.stratumPort)),
            (stratumUser, systemInfo.stratumUser),
            (fallbackStratumURL, systemInfo.fallbackStratumURL),
            (fallbackStratumPort.map { String($0) }, systemInfo.fallbackStratumPort.map { String($0) }),
            (fallbackStratumUser, systemInfo.fallbackStratumUser),
            (stratumProtocol, systemInfo.stratumProtocol),
            (fallbackStratumProtocol, systemInfo.fallbackStratumProtocol),
            (stratumV2ChannelType, systemInfo.stratumV2ChannelType),
            (fallbackStratumV2ChannelType, systemInfo.fallbackStratumV2ChannelType),
            (stratumV2AuthorityPubkey, systemInfo.stratumV2AuthorityPubkey),
            (fallbackStratumV2AuthorityPubkey, systemInfo.fallbackStratumV2AuthorityPubkey),
        ]
        return values.contains { sent, reported in
            guard let sent else { return false }
            return sent != (reported ?? "")
        }
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

    private static let poolSettingsNotAppliedMessage =
        "The miner accepted the request but did not apply the pool settings. Please try again, or change the pool from the miner web UI."

    private static let activePoolNotAppliedMessage =
        "The miner is restarting but has not confirmed the active pool change yet. Check Pool Settings again in a moment, or change the active pool from the miner web UI."

    private static let activePoolRestartFailedMessage =
        "The active pool was saved but the miner could not be restarted. Restart the miner to apply the change."

    private static let poolCatalogUnsupportedMessage =
        "This miner no longer reports its pool list. Reopen Pool Settings and try again."

    private static let poolCatalogRestartFailedMessage =
        "The pool settings were saved but the miner could not be restarted. Restart the miner to apply the change."

    private static let poolCatalogRestartNotConfirmedMessage =
        "The miner is restarting but has not confirmed the pool changes yet. Check Pool Settings again in a moment, or verify them from the miner web UI."

    private static let fallbackPoolRequiredMessage =
        "Enter the fallback pool host, port and user before selecting it as the active pool."

    private static let settingsConfigurationUnavailableMessage =
        "Miner settings are unavailable because this firmware returned an unsupported settings format. Metrics are still available, but use the miner web UI to change settings."

}
