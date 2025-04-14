import Combine
import Foundation
import Network
import SwiftUI
import WidgetKit

enum ScanInitiationResult {
    case success
    case permissionDenied
    case alreadyScanning
}

struct DiscoveredDevice: Identifiable {
    let id = UUID()
    let ip: String
    let name: String
    let hashrate: Double
    let temperature: Double
    let bestDiff: String
    let power: Double
    let poolURL: String?
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
        Task {
            _ = await checkLocalNetworkPermission()
            await checkAndUpdatePermission()
        }

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard let self = self else { return }

                if self.scanStatus
                    == "Please allow local network access in Settings to scan for devices"
                    && !self.isScanning
                {
                    self.scanStatus = ""
                }

                Task {
                    await self.checkAndUpdatePermission()
                }
            }
            .store(in: &cancellables)
    }

    private func checkAndUpdatePermission() async {
        hasLocalNetworkPermission = await checkLocalNetworkPermission()
        if !hasLocalNetworkPermission {
            scanStatus = "Please allow local network access in Settings to scan for devices"
        } else {
            if !isScanning {
                scanStatus = ""
            }
        }
    }

    private func checkLocalNetworkPermission() async -> Bool {
        let url = URL(string: "http://192.168.4.254")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0

        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            return true
        } catch {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet:
                    return false
                case .cannotConnectToHost, .networkConnectionLost, .timedOut:
                    return true
                default:
                    return false
                }
            }
            return false
        }
    }

    private func checkAPMode() async -> Bool {
        let apIP = "192.168.4.254"
        let urlString = "http://\(apIP)/api/system/info"
        guard let url = URL(string: urlString) else {
            return false
        }

        for attempt in 1...3 {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 5.0

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    continue
                }

                switch httpResponse.statusCode {
                case 200:
                    let decoder = JSONDecoder()
                    do {
                        let systemInfo = try decoder.decode(SystemInfoDTO.self, from: data)
                        if systemInfo.hostname.lowercased().contains("axe")
                            || systemInfo.version.lowercased().contains("axe")
                            || systemInfo.ASICModel.contains("BM1366")
                        {
                            let device = DiscoveredDevice(
                                ip: apIP,
                                name: systemInfo.hostname,
                                hashrate: systemInfo.hashrate ?? 0.0,
                                temperature: systemInfo.temperature ?? 0.0,
                                bestDiff: systemInfo.bestDiff,
                                power: systemInfo.power ?? 0.0,
                                poolURL: systemInfo.poolURL
                            )
                            await MainActor.run {
                                if !discoveredDevices.contains(where: { $0.ip == apIP }) {
                                    discoveredDevices.append(device)
                                    let deviceCount = discoveredDevices.count
                                    scanStatus =
                                        "Found \(deviceCount) device\(deviceCount == 1 ? "" : "s")..."
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
                }
            }

            if attempt < 3 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        return false
    }

    func startScan() async -> ScanInitiationResult {
        await checkAndUpdatePermission()

        guard hasLocalNetworkPermission else {
            scanStatus = "Please allow local network access in Settings to scan for devices"
            isScanning = false
            hasScanned = true
            return .permissionDenied
        }

        guard !isScanning else { return .alreadyScanning }

        isScanning = true
        scanStatus = "Scanning for devices..."
        discoveredDevices.removeAll()
        showErrorAlert = false
        hasScanned = false

        let foundInAPMode = await checkAPMode()
        if foundInAPMode {
        }

        if let interfaces = getNetworkInterfaces() {
            if let localNetwork = interfaces.first {
                let detectedBaseIP = localNetwork.split(separator: ".").dropLast().joined(
                    separator: "."
                )

                let subnetsToScan: Set<String> = [detectedBaseIP]

                Task {
                    await scanState.cancelAll()
                }

                for subnetBaseIP in subnetsToScan {
                    for i in 1...254 {
                        let ip = "\(subnetBaseIP).\(i)"
                        let task = Task { [weak self] in
                            guard let self = self, !Task.isCancelled else {
                                return
                            }
                            guard self.isScanning else { return }

                            do {
                                let discoveredDevice =
                                    try await DeviceManagementService.checkDevice(ip: ip)
                                await MainActor.run {
                                    if self.isScanning,
                                        !self.discoveredDevices.contains(where: { $0.ip == ip })
                                    {
                                        self.discoveredDevices.append(discoveredDevice)
                                        let deviceCount = self.discoveredDevices.count
                                        self.scanStatus =
                                            "Found \(deviceCount) device\(deviceCount == 1 ? "" : "s")..."
                                    }
                                }
                            } catch {
                            }

                        }
                        await self.scanState.add(task)
                    }
                }
            } else {
                handleError(
                    "Could not determine a local network interface to scan."
                )
                isScanning = false
                return .permissionDenied
            }
        } else {
            handleError(
                "Could not find any suitable network interfaces on your device."
            )
            isScanning = false
            return .permissionDenied
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self, self.isScanning else { return }
            Task { [weak self] in
                await self?.scanState.cancelAll()
            }
            if self.discoveredDevices.isEmpty {
                self.handleError(
                    """
                    No devices found.
                    """
                )
            } else {
                let deviceCount = self.discoveredDevices.count
                self.scanStatus =
                    "Scan complete. Found \(deviceCount) device\(deviceCount == 1 ? "" : "s")."
            }
            self.isScanning = false
            self.hasScanned = true
        }
        return .success
    }

    func selectDevice(_ device: DiscoveredDevice) {
        let savedDevice = SavedDevice(name: device.name, ipAddress: device.ip)

        do {
            try DeviceManagementService.saveDevice(savedDevice)
        } catch {
            handleError("Failed to save the selected device. Please try again.")
        }
    }

    func connectManually() async -> Bool {
        let ip = manualIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        let ipRegex =
            #"^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"#
        guard ip.range(of: ipRegex, options: .regularExpression) != nil else {
            handleError("Please enter a valid IP address (e.g., 192.168.1.100)")
            return false
        }

        do {
            let discoveredDevice = try await DeviceManagementService.checkDevice(ip: ip)

            let deviceToSave = SavedDevice(
                name: discoveredDevice.name,
                ipAddress: discoveredDevice.ip
            )
            try DeviceManagementService.saveDevice(deviceToSave)

            await MainActor.run {
                if !discoveredDevices.contains(where: { $0.ip == ip }) {
                    discoveredDevices.append(discoveredDevice)
                }
            }

            return true

        } catch let error as DeviceCheckError {
            handleError(error.localizedDescription)
            return false
        } catch {
            handleError("An unexpected error occurred while adding the device.")
            return false
        }
    }

    private func getNetworkInterfaces() -> [String]? {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            let interface = ptr?.pointee
            let addrFamily = interface?.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                guard let nameBytes = interface?.ifa_name,
                    let name = String(cString: nameBytes, encoding: .utf8)
                else {
                    continue
                }
                var rawHostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    interface?.ifa_addr,
                    socklen_t((interface?.ifa_addr.pointee.sa_len)!),
                    &rawHostname,
                    socklen_t(rawHostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                }

                if name == "en0" || name == "en1" {
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
                    }
                }
            }
        }

        if addresses.isEmpty {
            return nil
        }
        return addresses
    }

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
