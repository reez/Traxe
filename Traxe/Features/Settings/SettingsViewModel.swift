import Combine
import Foundation
import Network
import SwiftUI  // For @MainActor
import WidgetKit  // Import WidgetKit

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var bitaxeIPAddress: String = ""
    @Published var tempAlertThreshold: Double = 85.0  // Default threshold
    @Published var hashrateAlertThreshold: Double = 400.0  // Default threshold GH/s
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

    // Access UserDefaults directly or via a dedicated service
    private let userDefaults: UserDefaults
    private let networkService: NetworkService
    private var networkMonitor: NWPathMonitor?

    init(userDefaults: UserDefaults = .standard, networkService: NetworkService = NetworkService())
    {
        self.userDefaults = userDefaults
        self.networkService = networkService
        loadSettings()
        setupNetworkMonitoring()
        Task {
            await checkCurrentVersion()
        }
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
        // Only act if the network status has changed
        let wasConnected = isConnected
        let isNowConnected = path.status == .satisfied

        if wasConnected != isNowConnected {
            Task {
                if isNowConnected {
                    // Network came back, try to reconnect
                    await checkCurrentVersion()
                } else {
                    // Network went away, update UI
                    isConnected = false
                }
            }
        }
    }

    func loadSettings() {
        bitaxeIPAddress = userDefaults.string(forKey: "bitaxeIPAddress") ?? ""
        tempAlertThreshold = userDefaults.double(forKey: "tempAlertThreshold")
        if tempAlertThreshold == 0 { tempAlertThreshold = 85.0 }  // Set default if not found

        hashrateAlertThreshold = userDefaults.double(forKey: "hashrateAlertThreshold")
        if hashrateAlertThreshold == 0 { hashrateAlertThreshold = 400.0 }  // Set default

        Task {
            await fetchFanSettings()
        }
    }

    func saveSettings() {
        // Basic validation
        let trimmedIP = bitaxeIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIP.isEmpty /* Add more IP validation if needed */ else {
            // Optionally show an error to the user
            return
        }

        // Keep writing to standard defaults
        userDefaults.set(trimmedIP, forKey: "bitaxeIPAddress")
        userDefaults.set(tempAlertThreshold, forKey: "tempAlertThreshold")
        userDefaults.set(hashrateAlertThreshold, forKey: "hashrateAlertThreshold")

        // ALSO write IP to shared defaults
        if let sharedDefaults = UserDefaults(suiteName: "group.matthewramsden.traxe") {
            sharedDefaults.set(trimmedIP, forKey: "bitaxeIPAddress")
            print("Mirrored IP \(trimmedIP) to shared defaults during save.")  // Optional debugging
            // Reload widget timeline
            WidgetCenter.shared.reloadTimelines(ofKind: "TraxeWidget")
        } else {
            print("Error: Could not access shared UserDefaults in saveSettings to mirror IP.")
        }
    }

    func requestResetConfirmation() {
        showingResetConfirmation = true
    }

    func performReset() {
        // Clear relevant UserDefaults (standard)
        userDefaults.removeObject(forKey: "bitaxeIPAddress")
        userDefaults.removeObject(forKey: "tempAlertThreshold")
        userDefaults.removeObject(forKey: "hashrateAlertThreshold")
        // Add any other keys that need resetting

        // ALSO clear from shared defaults
        if let sharedDefaults = UserDefaults(suiteName: "group.matthewramsden.traxe") {
            sharedDefaults.removeObject(forKey: "bitaxeIPAddress")
            print("Removed IP from shared defaults during reset.")  // Optional debugging
        } else {
            print("Error: Could not access shared UserDefaults in performReset to remove IP.")
        }

        // Reload settings in the view model to reflect cleared state
        loadSettings()
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

    // MARK: - Update Flow
    /*
     The flow is now:
     User taps "Check for Updates"
     Shows loading indicator
     Fetches current system info
     If successful:
       Shows update confirmation alert
       If user confirms, starts OTA update
     If fails:
       Shows error message
     */
    func checkForUpdates() async {
        isUpdating = true
        updateError = nil

        do {
            let systemInfo = try await networkService.fetchSystemInfo()
            currentVersion = systemInfo.version

            // For now, we'll assume an update is available if we can connect
            // TODO: Add proper version comparison when we have a way to get latest version
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
            // Start OTA update
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

    func fetchFanSettings() async {
        do {
            let systemInfo = try await networkService.fetchSystemInfo()
            fanSpeed = systemInfo.fanspeed
            isAutoFan = systemInfo.autofanspeed != 0
        } catch {
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

    deinit {
        networkMonitor?.cancel()
    }
}
