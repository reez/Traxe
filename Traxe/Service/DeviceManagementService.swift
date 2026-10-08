import Foundation
import WidgetKit

struct DeviceManagementService {
    static let appGroupID = "group.matthewramsden.traxe"
    static var sharedDefaultsOverride: UserDefaults?
    static var onboardingDefaultsOverride: UserDefaults?
    static var reloadWidgetTimelines: (_ kind: String) -> Void = { kind in
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }

    private static let decoder = JSONDecoder()
    private static let savedDevicesKey = "savedDevices"
    private static let savedDeviceIPsKey = "savedDeviceIPs"
    private static let savedDeviceMACAddressesKey = "savedDeviceMACAddresses"
    private static let selectedDeviceKey = "bitaxeIPAddress"
    private static let hasCompletedOnboardingKey = "hasCompletedOnboarding"

    private static var sharedDefaults: UserDefaults? {
        sharedDefaultsOverride ?? UserDefaults(suiteName: appGroupID)
    }

    private static var onboardingDefaults: UserDefaults {
        onboardingDefaultsOverride ?? .standard
    }

    static func checkDevice(
        ip: String,
        timeout: TimeInterval = 5.0,
        retryOnTimeout: Bool = true,
        fetchData: (_ request: URLRequest) async throws -> (Data, URLResponse) = { request in
            try await URLSession.shared.data(for: request)
        }
    ) async throws -> DiscoveredDevice {
        let urlString = "http://\(ip)/api/system/info"
        guard let url = URL(string: urlString) else {
            throw DeviceCheckError.invalidURL
        }

        var request = URLRequest(url: url)
        // Slightly higher timeout to reduce -1001 churn on local devices
        request.timeoutInterval = timeout

        do {
            try Task.checkCancellation()
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await fetchData(request)
            } catch let error as URLError where error.code == .timedOut && retryOnTimeout {
                // Retry once on timeout, unless the caller has cancelled the check.
                try Task.checkCancellation()
                (data, response) = try await fetchData(request)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw DeviceCheckError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                do {
                    let telemetry = try decoder.decode(MinerTelemetryDTO.self, from: data)
                    let hashrate = telemetry.hashrate
                    let temperature = telemetry.temperature
                    let miningPaused = telemetry.miningPaused

                    if telemetry.isCompatibleMiner {
                        return DiscoveredDevice(
                            ip: ip,
                            name: telemetry.hostname,
                            hashrate: hashrate ?? 0.0,
                            temperature: temperature ?? 0.0,
                            bestDiff: telemetry.bestDiff,
                            power: telemetry.power ?? 0.0,
                            poolURL: telemetry.poolURL,
                            blockHeight: telemetry.blockHeight,
                            networkDifficulty: telemetry.networkDifficulty,
                            isHashrateKnown: hashrate != nil,
                            isTemperatureKnown: temperature != nil,
                            isMiningPaused: miningPaused ?? false,
                            isMiningPausedKnown: miningPaused != nil,
                            macAddress: SavedDevice.normalizedMACAddress(telemetry.mac)
                        )
                    } else {
                        throw DeviceCheckError.notBitaxeDevice
                    }
                } catch let error as DeviceCheckError {
                    throw error
                } catch let swiftDecodingError as Swift.DecodingError {
                    var fieldName: String? = nil
                    switch swiftDecodingError {
                    case .typeMismatch(_, let context):
                        fieldName = context.codingPath.last?.stringValue
                    case .valueNotFound(_, let context):
                        fieldName = context.codingPath.last?.stringValue
                    case .keyNotFound(_, let context):
                        fieldName = context.codingPath.last?.stringValue
                    case .dataCorrupted(let context):
                        fieldName = context.codingPath.last?.stringValue
                    @unknown default:
                        fieldName = nil
                    }
                    throw DeviceCheckError.decodingError(
                        field: fieldName,
                        swiftError: swiftDecodingError,
                        jsonData: data
                    )
                } catch {
                    throw DeviceCheckError.decodingError(
                        field: nil,
                        swiftError: nil,
                        jsonData: data
                    )
                }
            case 404:
                throw DeviceCheckError.notBitaxeDevice
            default:
                throw DeviceCheckError.invalidResponse
            }
        } catch let error as CancellationError {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled {
                throw error
            }
            throw DeviceCheckError.requestFailed(error.code)
        } catch let error as DeviceCheckError {
            throw error
        } catch {
            throw DeviceCheckError.unknown(error)
        }
    }

    static func saveDevice(_ deviceToSave: SavedDevice) throws {
        try saveDevices([deviceToSave])
    }

    static func saveNewDevice(_ deviceToSave: SavedDevice) throws {
        guard let sharedDefaults else {
            throw NSError(
                domain: "DeviceSaveError",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot access shared storage."]
            )
        }
        guard !loadSavedDevices(from: sharedDefaults).contains(where: {
            $0.ipAddress == deviceToSave.ipAddress
        }) else {
            throw DeviceSaveError.addressAlreadySaved
        }
        try saveDevice(deviceToSave)
    }

    static func saveDevices(_ devicesToSave: [SavedDevice]) throws {
        guard !devicesToSave.isEmpty else { return }

        guard let sharedDefaults else {
            throw NSError(
                domain: "DeviceSaveError",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot access shared storage."]
            )
        }

        var savedDevices = loadSavedDevices(from: sharedDefaults)
        var savedDeviceIPs = Set(savedDevices.map(\.ipAddress))
        var firstAddedIPAddress: String?
        var relocations: [DeviceRelocation] = []

        for deviceToSave in devicesToSave where !savedDeviceIPs.contains(deviceToSave.ipAddress) {
            // A saved miner answering at a new address is the same miner moved by DHCP,
            // not a second miner: it keeps its entry and everything keyed on it.
            if let macAddress = deviceToSave.macAddress,
                let index = uniqueIndex(ofDeviceWithMACAddress: macAddress, in: savedDevices)
            {
                let previousIPAddress = savedDevices[index].ipAddress
                savedDevices[index].ipAddress = deviceToSave.ipAddress
                savedDeviceIPs.remove(previousIPAddress)
                savedDeviceIPs.insert(deviceToSave.ipAddress)
                relocations.append(
                    DeviceRelocation(
                        macAddress: macAddress,
                        previousIPAddress: previousIPAddress,
                        currentIPAddress: deviceToSave.ipAddress
                    )
                )
                continue
            }

            savedDevices.append(deviceToSave)
            savedDeviceIPs.insert(deviceToSave.ipAddress)

            if firstAddedIPAddress == nil {
                firstAddedIPAddress = deviceToSave.ipAddress
            }
        }

        guard firstAddedIPAddress != nil || !relocations.isEmpty else {
            // Selecting an already saved miner also completes onboarding.
            onboardingDefaults.set(true, forKey: hasCompletedOnboardingKey)
            return
        }

        recordRelocations(relocations, in: &savedDevices)
        try persistSavedDevices(savedDevices, in: sharedDefaults)
        applyRelocationSideEffects(relocations, in: sharedDefaults)

        if let firstAddedIPAddress {
            sharedDefaults.set(firstAddedIPAddress, forKey: selectedDeviceKey)
        }
        onboardingDefaults.set(true, forKey: hasCompletedOnboardingKey)

        reloadWidgetTimelines("TraxeWidget")
    }

    /// Records the MAC address a saved miner reported, giving it the stable identity
    /// that lets Traxe follow it when DHCP hands it a different IP address.
    static func recordMACAddress(_ macAddress: String, forDeviceAt ipAddress: String) throws {
        guard let sharedDefaults else {
            throw NSError(
                domain: "DeviceIdentityError",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot access shared storage."]
            )
        }
        guard let normalizedMACAddress = SavedDevice.normalizedMACAddress(macAddress) else {
            return
        }

        var savedDevices = loadSavedDevices(from: sharedDefaults)
        guard let index = savedDevices.firstIndex(where: { $0.ipAddress == ipAddress }),
            savedDevices[index].macAddress != normalizedMACAddress
        else {
            return
        }

        savedDevices[index].macAddress = normalizedMACAddress
        try persistSavedDevices(savedDevices, in: sharedDefaults)
    }

    /// Moves saved miners to the addresses where `discoveredDevices` found their MAC
    /// addresses, carrying the selected miner, alert opt-ins, and widget identifiers
    /// along. Returns the moves that were applied.
    ///
    /// A MAC address saved on more than one entry is left alone, as is a move onto an
    /// address still held by a miner that is not moving in the same batch: either would
    /// need a guess about which entry to keep. Miners that swapped addresses move
    /// together.
    static func relocateDevices(
        matching discoveredDevices: [DiscoveredDevice]
    ) throws -> [DeviceRelocation] {
        guard let sharedDefaults else {
            throw NSError(
                domain: "DeviceRelocationError",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot access shared storage."]
            )
        }

        var savedDevices = loadSavedDevices(from: sharedDefaults)
        var currentIPAddressByIndex: [Int: String] = [:]
        var claimedIPAddresses: Set<String> = []

        for discovered in discoveredDevices {
            guard let macAddress = SavedDevice.normalizedMACAddress(discovered.macAddress),
                let index = uniqueIndex(ofDeviceWithMACAddress: macAddress, in: savedDevices),
                savedDevices[index].ipAddress != discovered.ip,
                claimedIPAddresses.insert(discovered.ip).inserted
            else { continue }
            currentIPAddressByIndex[index] = discovered.ip
        }

        // An address still held by a miner that is not vacating it stays with that miner.
        // Dropping one move can strand another that was moving into its old address, so
        // repeat until the set is stable.
        let heldIPAddresses = Set(savedDevices.map(\.ipAddress))
        var didDropMove = true
        while didDropMove {
            let vacatedIPAddresses = Set(
                currentIPAddressByIndex.keys.map { savedDevices[$0].ipAddress }
            )
            let stableMoves = currentIPAddressByIndex.filter { _, currentIPAddress in
                !heldIPAddresses.contains(currentIPAddress)
                    || vacatedIPAddresses.contains(currentIPAddress)
            }
            didDropMove = stableMoves.count != currentIPAddressByIndex.count
            currentIPAddressByIndex = stableMoves
        }

        guard !currentIPAddressByIndex.isEmpty else { return [] }

        var relocations: [DeviceRelocation] = []
        for (index, currentIPAddress) in currentIPAddressByIndex.sorted(by: { $0.key < $1.key }) {
            guard let macAddress = savedDevices[index].macAddress else { continue }
            relocations.append(
                DeviceRelocation(
                    macAddress: macAddress,
                    previousIPAddress: savedDevices[index].ipAddress,
                    currentIPAddress: currentIPAddress
                )
            )
            savedDevices[index].ipAddress = currentIPAddress
        }

        recordRelocations(relocations, in: &savedDevices)
        try persistSavedDevices(savedDevices, in: sharedDefaults)
        applyRelocationSideEffects(relocations, in: sharedDefaults)
        reloadWidgetTimelines("TraxeWidget")

        return relocations
    }

    /// Probes every host on this device's Wi-Fi /24 except its own address and
    /// `excludedIPAddresses`, returning the miners that answered. This looks for saved
    /// miners DHCP moved, so it uses short timeouts and bounded concurrency.
    static func scanLocalNetwork(
        excluding excludedIPAddresses: Set<String>
    ) async -> [DiscoveredDevice] {
        guard let ownAddress = localIPv4Address() else { return [] }
        let octets = ownAddress.split(separator: ".")
        guard octets.count == 4 else { return [] }
        let base = octets.prefix(3).joined(separator: ".")
        let hosts = (1...254)
            .map { "\(base).\($0)" }
            .filter { $0 != ownAddress && !excludedIPAddresses.contains($0) }

        return await withTaskGroup(of: DiscoveredDevice?.self) { group in
            var results: [DiscoveredDevice] = []
            var iterator = hosts.makeIterator()
            var inFlight = 0
            let maxConcurrent = 32

            func addNext() {
                guard let host = iterator.next() else { return }
                inFlight += 1
                group.addTask {
                    try? await checkDevice(ip: host, timeout: 1.0, retryOnTimeout: false)
                }
            }

            for _ in 0..<maxConcurrent { addNext() }
            while inFlight > 0 {
                guard let result = await group.next() else { break }
                inFlight -= 1
                if let result { results.append(result) }
                addNext()
            }
            return results
        }
    }

    /// The MAC address of each saved miner that has one, keyed by IP address, in the
    /// shape the widget reads to give placed widgets a stable miner identifier.
    static func macAddressesByIPAddress(_ devices: [SavedDevice]) -> [String: String] {
        var macAddresses: [String: String] = [:]
        for device in devices {
            if let macAddress = device.macAddress {
                macAddresses[device.ipAddress] = macAddress
            }
        }
        return macAddresses
    }

    static func deleteDevice(ipAddressToDelete: String) throws {
        guard let sharedDefaults else {
            throw NSError(
                domain: "DeviceDeleteError",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot access shared storage."]
            )
        }

        var savedDevices = loadSavedDevices(from: sharedDefaults)

        let initialCount = savedDevices.count
        savedDevices.removeAll { $0.ipAddress == ipAddressToDelete }

        guard savedDevices.count < initialCount else {
            return
        }

        do {
            try persistSavedDevices(savedDevices, in: sharedDefaults)

            if let currentIP = sharedDefaults.string(forKey: selectedDeviceKey),
                currentIP == ipAddressToDelete
            {
                sharedDefaults.removeObject(forKey: selectedDeviceKey)
            }

            // A deleted miner must not keep alerting, and re-adding its IP starts fresh.
            MinerAlertPreferences(defaults: sharedDefaults).removePreference(
                for: ipAddressToDelete
            )
            // Its old identifiers must not follow the address to whichever miner gets it next.
            SavedDeviceAddressAliases(defaults: sharedDefaults).removeAliases(
                resolvingTo: ipAddressToDelete
            )

            reloadWidgetTimelines("TraxeWidget")

        } catch {
            throw error
        }
    }

    static func reorderDevices(_ devices: [SavedDevice]) throws {
        guard let sharedDefaults else {
            throw NSError(
                domain: "DeviceReorderError",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot access shared storage."]
            )
        }

        do {
            try persistSavedDevices(devices, in: sharedDefaults)

            reloadWidgetTimelines("TraxeWidget")
        } catch {
            throw error
        }
    }

    private static func loadSavedDevices(from defaults: UserDefaults) -> [SavedDevice] {
        guard let data = defaults.data(forKey: savedDevicesKey),
            let decoded = try? JSONDecoder().decode([SavedDevice].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private static func persistSavedDevices(_ devices: [SavedDevice], in defaults: UserDefaults)
        throws
    {
        let encoded = try JSONEncoder().encode(devices)
        defaults.set(encoded, forKey: savedDevicesKey)
        defaults.set(devices.map(\.ipAddress), forKey: savedDeviceIPsKey)
        defaults.set(macAddressesByIPAddress(devices), forKey: savedDeviceMACAddressesKey)
    }

    /// The address and its recovery record are encoded in one `savedDevices` value.
    /// Every member of a swap or cycle shares one operation and cutoff.
    private static func recordRelocations(
        _ relocations: [DeviceRelocation],
        in savedDevices: inout [SavedDevice]
    ) {
        guard !relocations.isEmpty else { return }
        let operationID = UUID().uuidString
        let sequence = (savedDevices.flatMap(\.relocationRecords).map(\.sequence).max() ?? 0) + 1
        let cutoff = Date()
        var recordedMACAddresses: Set<String> = []
        for relocation in relocations {
            guard recordedMACAddresses.insert(relocation.macAddress).inserted else { continue }
            guard let index = savedDevices.firstIndex(where: {
                $0.macAddress == relocation.macAddress
            }) else { continue }
            let currentIPAddress = savedDevices[index].ipAddress
            savedDevices[index].relocationRecords.append(
                SavedDevice.RelocationRecord(
                    operationID: operationID,
                    sequence: sequence,
                    previousIPAddress: relocation.previousIPAddress,
                    currentIPAddress: currentIPAddress,
                    cutoff: cutoff
                )
            )
        }
    }

    /// Moves everything keyed by a miner's previous address to its current one: the
    /// selected miner, alert opt-ins, and the aliases that keep older widget and
    /// Shortcut identifiers resolving. Applied as one batch so swapped addresses work.
    private static func applyRelocationSideEffects(
        _ relocations: [DeviceRelocation],
        in defaults: UserDefaults
    ) {
        guard !relocations.isEmpty else { return }

        var currentIPAddressByPrevious: [String: String] = [:]
        for relocation in relocations {
            currentIPAddressByPrevious[relocation.previousIPAddress] = relocation.currentIPAddress
        }

        if let selectedIPAddress = defaults.string(forKey: selectedDeviceKey),
            let currentIPAddress = currentIPAddressByPrevious[selectedIPAddress]
        {
            defaults.set(currentIPAddress, forKey: selectedDeviceKey)
        }
        MinerAlertPreferences(defaults: defaults).relocateOptIns(currentIPAddressByPrevious)
        SavedDeviceAddressAliases(defaults: defaults).recordMoves(currentIPAddressByPrevious)
    }

    /// The index of the one saved miner with this MAC address, or `nil` when none or
    /// several have it. Duplicates come from a miner re-added at a new address before
    /// identities were tracked, and picking one of them would be a guess.
    private static func uniqueIndex(
        ofDeviceWithMACAddress macAddress: String,
        in devices: [SavedDevice]
    ) -> Int? {
        let indices = devices.indices.filter { devices[$0].macAddress == macAddress }
        return indices.count == 1 ? indices[0] : nil
    }

    /// This device's IPv4 address on Wi-Fi, which decides the /24 a relocation scan covers.
    private static func localIPv4Address() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let interface = ptr?.pointee {
            defer { ptr = interface.ifa_next }
            guard let addr = interface.ifa_addr,
                addr.pointee.sa_family == UInt8(AF_INET),
                let nameBytes = interface.ifa_name,
                ["en0", "en1"].contains(String(cString: nameBytes))
            else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 {
                return String(cString: hostname, encoding: .utf8)
            }
        }
        return nil
    }
}

enum DeviceSaveError: Error, LocalizedError {
    case addressAlreadySaved

    var errorDescription: String? {
        "This IP address is already saved. If it now belongs to a different miner, remove the saved miner before adding its replacement."
    }
}

enum DeviceCheckError: Error, LocalizedError {
    case invalidURL
    case requestFailed(URLError.Code)
    case invalidResponse
    case decodingError(field: String?, swiftError: Swift.DecodingError?, jsonData: Data?)
    case notBitaxeDevice
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Internal error: Could not create URL for miner check."
        case .requestFailed(let code):
            switch code {
            case .timedOut:
                return "The request timed out. The miner might be offline or unreachable."
            case .cannotConnectToHost:
                return
                    "Cannot connect to the miner. Ensure it's powered on and on the same network."
            case .notConnectedToInternet:
                return "Please check your network connection."
            case .networkConnectionLost:
                return "The network connection was lost."
            default:
                return "A network error occurred (Code: \(code.rawValue))."
            }
        case .invalidResponse: return "Received invalid response from the miner IP."
        case .decodingError(let field, let swiftError, _):
            var baseMessage = "Could not understand the response from the miner"
            if let fieldName = field, !fieldName.isEmpty {
                baseMessage += ". Issue with data field: '\(fieldName)'"
            } else {
                baseMessage += " (malformed data)"
            }
            if let swiftError = swiftError {
                baseMessage += ". Details: \(swiftError.localizedDescription)"
            }
            return baseMessage
        case .notBitaxeDevice:
            return "The miner at this IP address doesn't appear to be compatible."
        case .unknown(let error): return "An unknown error occurred: \(error.localizedDescription)"
        }
    }
}
