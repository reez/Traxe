import Combine  // For ObservableObject
import Foundation
import Network
import SwiftUI  // For @MainActor
import WidgetKit // Import WidgetKit

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
            _ = await checkLocalNetworkPermission()
            await checkAndUpdatePermission()
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
            scanStatus = "Please allow local network access in Settings to scan for devices"
        } else {
            scanStatus = ""
        }
    }

    private func checkLocalNetworkPermission() async -> Bool {
        let url = URL(string: "http://192.168.4.254")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0  // Short timeout for permission check

        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            return true
        } catch {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet:
                    return false
                case .cannotConnectToHost:
                    return true  // Permission granted but host not available
                case .networkConnectionLost:
                    return true  // Permission granted but connection lost
                default:
                    return false
                }
            }
            return false
        }
    }

    private func checkAPMode() async -> Bool {
        let apIP = "192.168.4.254"

        // Try HTTP first (BitAxe doesn't support HTTPS)
        let urlString = "http://\(apIP)/api/system/info"
        guard let url = URL(string: urlString) else { return false }

        for attempt in 1...3 {

            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 5.0  // Longer timeout for AP mode

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
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
                                }
                            }
                            return true
                        } else {
                        }
                    } catch {
                    }
                case 404:
                    return false
                default:
                    return false
                }
            } catch {
                if let urlError = error as? URLError {
                    switch urlError.code {
                    case .timedOut:
                        return false
                    case .cannotConnectToHost:
                        return false
                    case .notConnectedToInternet:
                        return false
                    default:
                        return false
                    }
                } else {
                    return false
                }
            }

            // Wait before retry
            if attempt < 3 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second delay
            }
        }

        return false
    }

    func startScan() async {
        guard !isScanning else { return }

        isScanning = true
        scanStatus = "Scanning for BitAxe devices..."
        discoveredDevices.removeAll()
        showErrorAlert = false
        hasScanned = false

        // First try AP mode
        if await checkAPMode() {
            isScanning = false
            hasScanned = true
            return
        }

        // If AP mode failed, check if we're on a local network
        if let interfaces = getNetworkInterfaces(),
            let localNetwork = interfaces.first(where: { !$0.contains("192.168.4.") })
        {
            // We're on a regular network, scan it
            let baseIP = localNetwork.split(separator: ".").dropLast().joined(separator: ".")

            // Cancel any existing scan tasks
            Task {
                await scanState.cancelAll()
            }

            // Only scan a few likely IP addresses to avoid flooding
            let likelyIPs = [1, 100, 150, 200, 250, 254]
            for i in likelyIPs {
                let ip = "\(baseIP).\(i)"
                Task { [weak self] in
                    await self?.checkAddress(ip)
                    await self?.scanState.add(Task {})  // Add a dummy task to track for cancellation
                }
            }
        } else {
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
            if self.discoveredDevices.isEmpty {
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
                self.scanStatus = "Scan complete. Found \(self.discoveredDevices.count) device(s)."
            }
            Task { [weak self] in
                await self?.scanState.cancelAll()
            }
            self.isScanning = false
            self.hasScanned = true
        }
    }

    private func checkAddress(_ ip: String) async {
        let urlString = "http://\(ip)/api/system/info"
        guard let url = URL(string: urlString) else { return }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 3.0

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { return }

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
                            }
                        }
                    }
                }
            case 404:
                return
            default:
                return
            }
        } catch {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    return
                case .cannotConnectToHost:
                    return
                case .notConnectedToInternet:
                    return
                default:
                    return
                }
            } else {
                return
            }
        }
    }

    func selectDevice(_ device: DiscoveredDevice) {
        // Keep writing to standard defaults for the main app
        UserDefaults.standard.set(device.ip, forKey: "bitaxeIPAddress")

        // ALSO write to shared defaults for the widget/NetworkService
        if let sharedDefaults = UserDefaults(suiteName: "group.matthewramsden.traxe") {
            sharedDefaults.set(device.ip, forKey: "bitaxeIPAddress")
            print("Mirrored IP \(device.ip) to shared defaults.") // Optional: for debugging
            // Reload widget timeline
            WidgetCenter.shared.reloadTimelines(ofKind: "TraxeWidget")
        } else {
            print("Error: Could not access shared UserDefaults in selectDevice to mirror IP.")
        }
    }

    // Modified to return Bool indicating success
    func connectManually() async -> Bool {
        let ip = manualIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate IP format
        let ipRegex =
            #"^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"#
        guard ip.range(of: ipRegex, options: .regularExpression) != nil else {
            handleError("Please enter a valid IP address (e.g., 192.168.1.100)")
            // Return false on validation failure
            return false
        }

        // Check the address first
        await checkAddress(ip)

        // Now check if the device was added by checkAddress
        if let device = discoveredDevices.first(where: { $0.ip == ip }) {
            selectDevice(device)  // Save IP to UserDefaults
            // Return true on success
            return true
        } else {
            handleError(
                "Could not connect to BitAxe at \(ip). Please verify the IP address and ensure the device is powered on."
            )
            // Return false if device not found after check
            return false
        }
    }

    private func getNetworkInterfaces() -> [String]? {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            let interface = ptr?.pointee
            let addrFamily = interface?.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: (interface?.ifa_name)!)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface?.ifa_addr,
                        socklen_t((interface?.ifa_addr.pointee.sa_len)!),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    if let address = String(cString: hostname, encoding: .utf8) {
                        addresses.append(address)
                    }
                }
            }
        }

        return addresses.isEmpty ? nil : addresses
    }

    private func handleError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
        scanStatus = "Scan failed"
    }

    deinit {
        Task { [weak self] in
            await self?.scanState.cancelAll()
        }
    }
}
