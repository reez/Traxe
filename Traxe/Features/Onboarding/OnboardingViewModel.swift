import Combine  // For ObservableObject
import Foundation
import Network
import SwiftUI  // For @MainActor
import WidgetKit  // Import WidgetKit
import os.log

struct DiscoveredDevice: Identifiable {
    let id = UUID()
    let ip: String
    let name: String
    let hashrate: Double
    let temperature: Double
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var scanStatus: String = ""
    @Published var isScanning: Bool = false
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var showErrorAlert: Bool = false
    @Published var errorMessage: String = ""
    @Published var manualIPAddress: String = ""
    @Published var navigateToDashboard: Bool = false
    @Published var hasScanned: Bool = false
    @Published var showManualEntry: Bool = false
    @Published var hasLocalNetworkPermission: Bool = false

    private var browser: NWBrowser?
    private var cancellables = Set<AnyCancellable>()
    private let queue = DispatchQueue(
        label: "com.matthewramsden.traxe.discovery",
        qos: .userInitiated
    )

    // Use actor to synchronize access to scanTasks
    private actor ScanState {
        var tasks: [Task<Void, Never>] = []

        func add(_ task: Task<Void, Never>) {
            tasks.append(task)
        }

        func cancelAll() {
            tasks.forEach { $0.cancel() }
            tasks.removeAll()
        }
    }
    private let scanState = ScanState()

    init() {
        // Trigger permission check immediately
        Task {
            _ = await checkLocalNetworkPermission() // Initial check
            await checkAndUpdatePermission()        // Update state and potentially log
        }

        // Listen for app becoming active to recheck permission
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.checkAndUpdatePermission()
                }
            }
            .store(in: &cancellables)
    }

    private func checkAndUpdatePermission() async {
        hasLocalNetworkPermission = await checkLocalNetworkPermission()
        if !hasLocalNetworkPermission {
            Logger.onboarding.warning("Local network permission check failed or was denied.")
            scanStatus = "Please allow local network access in Settings to scan for devices"
        } else {
            Logger.onboarding.info("Local network permission granted.")
            scanStatus = ""
        }
    }

    private func checkLocalNetworkPermission() async -> Bool {
        let url = URL(string: "http://192.168.4.254")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0  // Short timeout for permission check

        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            Logger.onboarding.debug("Local network permission check succeeded (via dummy request).")
            return true
        } catch {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet:
                    Logger.onboarding.warning("Local network permission check failed: Not connected to internet.")
                    return false
                case .cannotConnectToHost:
                    // This case implies permission might be granted, but the dummy host isn't reachable.
                    // It's not a definitive 'granted' state, but doesn't mean 'denied'.
                    Logger.onboarding.debug("Local network permission check: Cannot connect to dummy host (may still have permission).")
                    return true
                case .networkConnectionLost:
                     Logger.onboarding.debug("Local network permission check: Network connection lost (may still have permission).")
                    return true
                default:
                    Logger.onboarding.error("Local network permission check failed with unexpected URLError: \(urlError.localizedDescription)")
                    return false
                }
            }
            Logger.onboarding.error("Local network permission check failed with unexpected error: \(error.localizedDescription)")
            return false
        }
    }

    private func checkAPMode() async -> Bool {
        let apIP = "192.168.4.254"
        Logger.onboarding.info("Checking for device in AP mode.")
        // Try HTTP first (BitAxe doesn't support HTTPS)
        let urlString = "http://\(apIP)/api/system/info"
        guard let url = URL(string: urlString) else {
            Logger.onboarding.error("Failed to create URL for AP mode check.")
            return false
        }

        for attempt in 1...3 {
            Logger.onboarding.debug("AP mode check attempt \(attempt)...")
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 5.0  // Longer timeout for AP mode

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.onboarding.warning("AP mode check attempt \(attempt): Invalid HTTP response.")
                    continue
                }

                switch httpResponse.statusCode {
                case 200:
                    let decoder = JSONDecoder()
                    do {
                        let systemInfo = try decoder.decode(SystemInfoDTO.self, from: data)
                        // Verify it's a BitAxe by checking properties
                        if systemInfo.hostname.lowercased().contains("axe")
                            || systemInfo.version.lowercased().contains("axe")
                            || systemInfo.ASICModel.contains("BM1366")
                        {
                            let device = DiscoveredDevice(
                                ip: apIP,
                                name: systemInfo.hostname,
                                hashrate: systemInfo.hashrate ?? 0.0,
                                temperature: systemInfo.temperature ?? 0.0
                            )
                            await MainActor.run {
                                if !discoveredDevices.contains(where: { $0.ip == apIP }) {
                                    discoveredDevices.append(device)
                                    scanStatus = ""
                                    Logger.onboarding.info("Found BitAxe in AP mode: \(systemInfo.hostname).")
                                }
                            }
                            return true
                        } else {
                            Logger.onboarding.warning("AP mode check attempt \(attempt): Device responded but doesn't seem to be a BitAxe.")
                        }
                    } catch {
                        Logger.onboarding.warning("AP mode check attempt \(attempt): Failed to decode response: \(error.localizedDescription)")
                    }
                case 404:
                    Logger.onboarding.debug("AP mode check attempt \(attempt): Got 404.")
                    return false // 404 means no device here
                default:
                    Logger.onboarding.warning("AP mode check attempt \(attempt): Received unexpected status code \(httpResponse.statusCode).")
                    return false // Treat other statuses as failure for this check
                }
            } catch {
                if let urlError = error as? URLError {
                    switch urlError.code {
                    case .timedOut:
                         Logger.onboarding.debug("AP mode check attempt \(attempt): Timed out connecting.")
                    case .cannotConnectToHost:
                         Logger.onboarding.debug("AP mode check attempt \(attempt): Cannot connect to host.")
                    case .notConnectedToInternet:
                         Logger.onboarding.warning("AP mode check attempt \(attempt): Failed - Not connected to internet.")
                         return false // Can't proceed without internet
                    default:
                         Logger.onboarding.warning("AP mode check attempt \(attempt): URLError connecting: \(urlError.localizedDescription)")
                    }
                } else {
                    Logger.onboarding.error("AP mode check attempt \(attempt): Unexpected error connecting: \(error.localizedDescription)")
                }
                 // Don't return false immediately on recoverable errors, let it retry
            }

            // Wait before retry
            if attempt < 3 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second delay
            }
        }
        Logger.onboarding.info("AP mode check completed after 3 attempts, device not found.")
        return false
    }

    func startScan() async {
        guard hasLocalNetworkPermission else {
            Logger.onboarding.warning("Scan aborted: Local network permission not granted.")
            scanStatus = "Please allow local network access in Settings to scan for devices"
            isScanning = false // Ensure scanning is marked as stopped
            hasScanned = true // Mark as scanned (attempted)
            return
        }

        guard !isScanning else { return }

        isScanning = true
        scanStatus = "Scanning for BitAxe devices..."
        discoveredDevices.removeAll()
        showErrorAlert = false
        hasScanned = false
        Logger.onboarding.info("Starting device scan.")

        // First try AP mode
        if await checkAPMode() {
            Logger.onboarding.info("Scan finished: Found device in AP mode.")
            isScanning = false
            hasScanned = true
            return
        }

        // If AP mode failed, check if we're on a local network
        if let interfaces = getNetworkInterfaces(),
            let localNetwork = interfaces.first(where: { !$0.contains("192.168.4.") })
        {
             Logger.onboarding.info("AP mode check failed. Scanning local network...")
            // We're on a regular network, scan it
            let baseIP = localNetwork.split(separator: ".").dropLast().joined(separator: ".")

            // Cancel any existing scan tasks
            Task {
                await scanState.cancelAll()
            }

            // Only scan a few likely IP addresses to avoid flooding
            let likelyIPs = [1, 100, 150, 200, 250, 254]
            Logger.onboarding.debug("Scanning likely local IPs.")
            for i in likelyIPs {
                let ip = "\(baseIP).\(i)"
                Task { [weak self] in
                    await self?.checkAddress(ip)
                    await self?.scanState.add(Task {})  // Add a dummy task to track for cancellation
                }
            }
        } else {
            Logger.onboarding.warning("Could not determine local network interface or only connected to AP mode network.")
            handleError(
                """
                Could not connect to BitAxe in AP mode. Please ensure:
                1. The BitAxe is powered on
                2. You're connected to the BitAxe's WiFi network (SSID: bitaxe-xxxx)
                3. Wait a few seconds after connecting to the WiFi before scanning
                """
            )
            isScanning = false
            return
        }

        // Set a timeout for local network scan
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, self.isScanning else { return }
            Task { [weak self] in // Ensure cancellation happens
                 await self?.scanState.cancelAll()
            }
            if self.discoveredDevices.isEmpty {
                Logger.onboarding.warning("Scan timed out after 10 seconds. No devices found.")
                self.handleError(
                    """
                    No BitAxe devices found. Please ensure:
                    1. The BitAxe is powered on
                    2. You're either:
                       - Connected to the BitAxe's WiFi network (SSID: bitaxe-xxxx), or
                       - The BitAxe is connected to your local network
                    """
                )
            } else {
                Logger.onboarding.info("Scan complete. Found \(self.discoveredDevices.count) device(s).")
                self.scanStatus = "Scan complete. Found \(self.discoveredDevices.count) device(s)."
            }
            self.isScanning = false
            self.hasScanned = true
        }
    }

    private func checkAddress(_ ip: String) async {
        let urlString = "http://\(ip)/api/system/info"
        guard let url = URL(string: urlString) else {
            Logger.onboarding.error("Failed to create URL for checking address.")
            return
        }
        Logger.onboarding.debug("Checking address...")

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 3.0

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.onboarding.warning("Invalid HTTP response from address.")
                return
            }

            switch httpResponse.statusCode {
            case 200:
                // Try to decode as SystemInfoDTO to verify it's a BitAxe
                let decoder = JSONDecoder()
                if let systemInfo = try? decoder.decode(SystemInfoDTO.self, from: data) {
                    // Verify it's a BitAxe by checking properties
                    if systemInfo.hostname.lowercased().contains("axe")
                        || systemInfo.version.lowercased().contains("axe")
                        || systemInfo.ASICModel.contains("BM1366")
                    {
                        let device = DiscoveredDevice(
                            ip: ip,
                            name: systemInfo.hostname,
                            hashrate: systemInfo.hashrate ?? 0.0,
                            temperature: systemInfo.temperature ?? 0.0
                        )
                        await MainActor.run {
                            if !discoveredDevices.contains(where: { $0.ip == ip }) {
                                discoveredDevices.append(device)
                                scanStatus = "Found \(discoveredDevices.count) device(s)..."
                                Logger.onboarding.info("Found BitAxe: \(systemInfo.hostname) at scanned address.")
                            }
                        }
                    } else {
                        Logger.onboarding.debug("Device at scanned address responded but doesn't seem to be a BitAxe.")
                    }
                } else {
                     Logger.onboarding.warning("Failed to decode response from scanned address as BitAxe SystemInfo.")
                }
            case 404:
                 Logger.onboarding.debug("Got 404 from scanned address.")
                return
            default:
                 Logger.onboarding.warning("Received unexpected status code \(httpResponse.statusCode) from scanned address.")
                return
            }
        } catch {
            if let urlError = error as? URLError {
                // Log only specific, potentially interesting errors at debug level
                switch urlError.code {
                case .timedOut, .cannotConnectToHost, .networkConnectionLost:
                    Logger.onboarding.debug("URLError checking scanned address: \(urlError.code.rawValue)")
                case .notConnectedToInternet:
                     Logger.onboarding.warning("Cannot check scanned address: Not connected to internet.")
                default:
                    Logger.onboarding.warning("Unexpected URLError checking scanned address: \(urlError.localizedDescription)")
                }
            } else {
                 Logger.onboarding.error("Unexpected error checking scanned address: \(error.localizedDescription)")
            }
        }
    }

    func selectDevice(_ device: DiscoveredDevice) {
        Logger.onboarding.info("Device selected: \(device.name).")
        // Keep writing to standard defaults for the main app
        UserDefaults.standard.set(device.ip, forKey: "bitaxeIPAddress")

        // ALSO write to shared defaults for the widget/NetworkService
        if let sharedDefaults = UserDefaults(suiteName: "group.matthewramsden.traxe") {
            sharedDefaults.set(device.ip, forKey: "bitaxeIPAddress")
            // Reload widget timeline
            WidgetCenter.shared.reloadTimelines(ofKind: "TraxeWidget")
        } else {
            Logger.onboarding.error("Failed to access shared UserDefaults group when selecting device.")
        }
    }

    // Modified to return Bool indicating success
    func connectManually() async -> Bool {
        let ip = manualIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        Logger.onboarding.info("Attempting manual connection.")

        // Validate IP format
        let ipRegex =
            #"^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"#
        guard ip.range(of: ipRegex, options: .regularExpression) != nil else {
            Logger.onboarding.warning("Manual connection failed: Invalid IP format entered.")
            handleError("Please enter a valid IP address (e.g., 192.168.1.100)")
            // Return false on validation failure
            return false
        }

        // Check the address first
        await checkAddress(ip)

        // Now check if the device was added by checkAddress
        if let device = discoveredDevices.first(where: { $0.ip == ip }) {
            Logger.onboarding.info("Manual connection successful to device: \(device.name).")
            selectDevice(device)  // Save IP to UserDefaults
            // Return true on success
            return true
        } else {
            Logger.onboarding.warning("Manual connection failed: Could not verify BitAxe device at the provided address after check.")
            handleError(
                "Could not connect to BitAxe at the entered address. Please verify the IP address and ensure the device is powered on."
            )
            // Return false if device not found after check
            return false
        }
    }

    private func getNetworkInterfaces() -> [String]? {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else {
             Logger.onboarding.error("Failed to get network interfaces: getifaddrs returned error.")
             return nil
        }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            let interface = ptr?.pointee
            let addrFamily = interface?.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) { // IPv4
                let name = String(cString: (interface?.ifa_name)!)
                if name == "en0" || name == "en1" { // WiFi or Ethernet
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(
                        interface?.ifa_addr,
                        socklen_t((interface?.ifa_addr.pointee.sa_len)!),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    ) == 0 {
                        if let address = String(cString: hostname, encoding: .utf8) {
                            addresses.append(address)
                        }
                    } else {
                        Logger.onboarding.warning("Failed to get IP address string for interface \(name).")
                    }
                }
            }
        }

        if addresses.isEmpty {
             Logger.onboarding.warning("Could not find suitable network interface.")
             return nil
        }
        Logger.onboarding.debug("Found network interfaces.")
        return addresses
    }

    // Helper to log all interface names for debugging
    private func getAllInterfaceNames(_ ifaddr: UnsafeMutablePointer<ifaddrs>?) -> [String] {
        var names: [String] = []
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            if let name = ptr?.pointee.ifa_name {
                 names.append(String(cString: name))
            }
        }
        return names.sorted()
    }


    private func handleError(_ message: String) {
        Logger.onboarding.error("Error handled: \(message)")
        errorMessage = message
        showErrorAlert = true
        scanStatus = "Scan failed"
    }

    deinit {
        Logger.onboarding.info("OnboardingViewModel deinitialized.")
        Task { [weak self] in
            await self?.scanState.cancelAll()
        }
    }
}
