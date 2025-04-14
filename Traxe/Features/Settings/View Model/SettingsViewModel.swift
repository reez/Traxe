import Combine
import Foundation
import Network
import SwiftData
import SwiftUI
import WidgetKit

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var bitaxeIPAddress: String = ""
    @Published var tempAlertThreshold: Double = 85.0
    @Published var hashrateAlertThreshold: Double = 400.0
    @Published var currentVersion: String = "Unknown"
    @Published var isUpdating: Bool = false
    @Published var updateError: String?
    @Published var showingUpdateConfirmation: Bool = false
    @Published var showingResetConfirmation: Bool = false
    @Published var showingPremiumSheet: Bool = false
    @Published var fanSpeed: Int = 0
    @Published var isAutoFan: Bool = true
    @Published var isUpdatingFan: Bool = false
    @Published var isConnected: Bool = false
    @Published var stratumUser: String = ""
    @Published var stratumURL: String = ""
    @Published var stratumPortString: String = ""
    @Published var isUpdatingPoolConfiguration: Bool = false
    @Published var poolConfigurationError: String? = nil
    @Published var hostname: String = ""
    @Published var isUpdatingHostname: Bool = false
    @Published var hostnameConfigurationError: String? = nil

    private let userDefaults: UserDefaults
    private let sharedUserDefaults: UserDefaults
    private let networkService: NetworkService
    private let modelContext: ModelContext
    private var networkMonitor: NWPathMonitor?

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

    private func setupNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            Task { [weak self] in
                await self?.handleNetworkPathUpdate(path)
            }
        }
        networkMonitor?.start(queue: DispatchQueue.global(qos: .background))
    }

    private func handleNetworkPathUpdate(_ path: NWPath) {
        let wasConnected = isConnected
        let isNowConnected = path.status == .satisfied

        if wasConnected != isNowConnected {
            Task {
                if isNowConnected {
                    isConnected = true
                } else {
                    isConnected = false
                }
            }
        }
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

    func openPremiumPage() {
        showingPremiumSheet = true
    }

    func checkCurrentVersion() async {
        do {
            let systemInfo = try await networkService.fetchSystemInfo()
            currentVersion = systemInfo.version
            isConnected = true
        } catch {
            currentVersion = "Unknown"
            isConnected = false
        }
    }

    func checkForUpdates() async {
        isUpdating = true
        updateError = nil

        do {
            let systemInfo = try await networkService.fetchSystemInfo()
            currentVersion = systemInfo.version

            showingUpdateConfirmation = true
        } catch {
            updateError = "Failed to check for updates: \(error.localizedDescription)"
        }

        isUpdating = false
    }

    func requestUpdateConfirmation() {
        Task {
            await checkForUpdates()
        }
    }

    func performUpdate() async {
        isUpdating = true
        updateError = nil

        do {
            try await networkService.updateFirmware()
            isUpdating = false
        } catch {
            isUpdating = false
            updateError = error.localizedDescription
        }
    }

    func restartDevice() async {
        do {
            try await networkService.restartDevice()
        } catch {
            updateError = error.localizedDescription
        }
    }

    func fetchDeviceSettings() async {
        do {
            let systemInfo = try await networkService.fetchSystemInfo()
            currentVersion = systemInfo.version
            fanSpeed = systemInfo.fanspeed ?? 0
            isAutoFan = systemInfo.autofanspeed != 0
            stratumUser = systemInfo.stratumUser
            stratumURL = systemInfo.stratumURL
            stratumPortString = String(systemInfo.stratumPort)
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
            try await networkService.updateSystemSettings(fanspeed: newSpeed)
            fanSpeed = newSpeed
        } catch {
        }
        isUpdatingFan = false
    }

    func savePoolConfiguration() async -> Bool {
        isUpdatingPoolConfiguration = true
        poolConfigurationError = nil
        var success = false

        var portToSave: Int? = nil
        if let port = Int(stratumPortString), !stratumPortString.isEmpty {
            portToSave = port
        } else if !stratumPortString.isEmpty {
            poolConfigurationError = "Invalid port number. Please enter a valid number."
            isUpdatingPoolConfiguration = false
            return false
        }

        do {
            try await networkService.updateSystemSettings(
                stratumUser: stratumUser.isEmpty ? nil : stratumUser,
                stratumURL: stratumURL.isEmpty ? nil : stratumURL,
                stratumPort: portToSave
            )
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

    deinit {
        networkMonitor?.cancel()
    }
}
