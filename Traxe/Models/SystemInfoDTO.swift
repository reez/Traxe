import Foundation

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

struct SystemInfoDTO: Codable {
    let power: Double?
    let voltage: Double?
    let current: Double?
    let temp: Double?
    let vrTemp: Double?
    let hashRate: Double?
    let expectedHashrate: Double?
    let _bestDiff: String?
    let bestSessionDiff: String?
    let stratumDiff: Int?

    let isUsingFallbackStratum: Int?
    let freeHeap: Int?
    let coreVoltage: Int?
    let coreVoltageActual: Int?
    let frequency: Int?

    let ssid: String?
    let macAddr: String?
    let _hostname: String?
    let wifiStatus: String?
    let wifiRSSI: Int?

    let sharesAccepted: Int?
    let sharesRejected: Int?
    let uptimeSeconds: Int?
    let blockHeight: Int?
    let networkDifficulty: Double?
    let blockFound: Int?

    let asicCount: Int?
    let smallCoreCount: Int?
    let _ASICModel: String?

    let _stratumURL: String?
    let fallbackStratumURL: String?
    let _stratumPort: Int?
    let fallbackStratumPort: Int?
    let _stratumUser: String?
    let fallbackStratumUser: String?

    let _version: String?
    let idfVersion: String?
    let boardVersion: String?
    let runningPartition: String?

    let flipscreen: Int?
    let overheat_mode: Int?
    let invertscreen: Int?
    let invertfanpolarity: Int?
    let autofanspeed: Int?
    let minimumFanSpeed: Int?
    let fanspeed: Int?
    let fanrpm: Int?

    // NerdQAxe-specific fields (optional, won't affect Bitaxe)
    let deviceModel: String?
    let hostip: String?
    let maxPower: Double?
    let minPower: Double?
    let maxVoltage: Double?
    let minVoltage: Double?
    let hashRateTimestamp: Int?
    let hashRate_10m: Double?
    let hashRate_1h: Double?
    let hashRate_1d: Double?
    let jobInterval: Int?
    let overheat_temp: Double?
    let autoscreenoff: Int?
    let lastResetReason: String?
    let stratum: StratumInfoDTO?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case power, voltage, current, temp, vrTemp
        case hashRate = "hashRate"
        case expectedHashrate
        case _bestDiff = "bestDiff"
        case bestSessionDiff, stratumDiff
        case isUsingFallbackStratum, freeHeap
        case coreVoltage, coreVoltageActual, frequency
        case ssid, macAddr
        case _hostname = "hostname"
        case wifiStatus, wifiRSSI
        case sharesAccepted, sharesRejected, uptimeSeconds
        case blockHeight, networkDifficulty, blockFound
        case asicCount, smallCoreCount
        case _ASICModel = "ASICModel"
        case _stratumURL = "stratumURL"
        case fallbackStratumURL
        case _stratumPort = "stratumPort"
        case fallbackStratumPort
        case _stratumUser = "stratumUser"
        case fallbackStratumUser
        case _version = "version"
        case idfVersion, boardVersion
        case runningPartition
        case flipscreen, overheat_mode
        case invertscreen, invertfanpolarity
        case autofanspeed, minimumFanSpeed, fanspeed, fanrpm

        // NerdQAxe-specific keys
        case deviceModel, hostip
        case maxPower, minPower
        case maxVoltage, minVoltage
        case hashRateTimestamp
        case hashRate_10m, hashRate_1h, hashRate_1d
        case jobInterval, overheat_temp
        case autoscreenoff, lastResetReason
        case stratum
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode all known fields as optional
        power = try container.decodeIfPresent(Double.self, forKey: .power)
        voltage = try container.decodeIfPresent(Double.self, forKey: .voltage)
        current = try container.decodeIfPresent(Double.self, forKey: .current)
        temp = try container.decodeIfPresent(Double.self, forKey: .temp)
        // Handle vrTemp - support both Int (Bitaxe) and Double (NerdQAxe)
        if let doubleValue = try? container.decode(Double.self, forKey: .vrTemp) {
            vrTemp = doubleValue
        } else if let intValue = try? container.decode(Int.self, forKey: .vrTemp) {
            vrTemp = Double(intValue)
        } else {
            vrTemp = nil
        }
        expectedHashrate = try container.decodeIfPresent(Double.self, forKey: .expectedHashrate)
        _bestDiff = Self.decodeDiffAsString(container: container, key: ._bestDiff)
        bestSessionDiff = Self.decodeDiffAsString(container: container, key: .bestSessionDiff)
        stratumDiff = try container.decodeIfPresent(Int.self, forKey: .stratumDiff)
        // Handle isUsingFallbackStratum - support both Bool (NerdQAxe) and Int (Bitaxe)
        if let boolValue = try? container.decode(Bool.self, forKey: .isUsingFallbackStratum) {
            isUsingFallbackStratum = boolValue ? 1 : 0  // Convert Bool to Int
        } else {
            isUsingFallbackStratum = try container.decodeIfPresent(
                Int.self,
                forKey: .isUsingFallbackStratum
            )
        }
        freeHeap = try container.decodeIfPresent(Int.self, forKey: .freeHeap)
        coreVoltage = try container.decodeIfPresent(Int.self, forKey: .coreVoltage)
        coreVoltageActual = try container.decodeIfPresent(Int.self, forKey: .coreVoltageActual)
        frequency = try container.decodeIfPresent(Int.self, forKey: .frequency)
        ssid = try container.decodeIfPresent(String.self, forKey: .ssid)
        macAddr = try container.decodeIfPresent(String.self, forKey: .macAddr)
        _hostname = try container.decodeIfPresent(String.self, forKey: ._hostname)
        wifiStatus = try container.decodeIfPresent(String.self, forKey: .wifiStatus)
        wifiRSSI = try container.decodeIfPresent(Int.self, forKey: .wifiRSSI)
        sharesAccepted = try container.decodeIfPresent(Int.self, forKey: .sharesAccepted)
        sharesRejected = try container.decodeIfPresent(Int.self, forKey: .sharesRejected)
        uptimeSeconds = try container.decodeIfPresent(Int.self, forKey: .uptimeSeconds)
        blockHeight = try container.decodeIfPresent(Int.self, forKey: .blockHeight)
        networkDifficulty = Self.decodeDoubleFlexible(container: container, key: .networkDifficulty)
        if let boolValue = try? container.decode(Bool.self, forKey: .blockFound) {
            blockFound = boolValue ? 1 : 0
        } else {
            blockFound = try container.decodeIfPresent(Int.self, forKey: .blockFound)
        }
        asicCount = try container.decodeIfPresent(Int.self, forKey: .asicCount)
        smallCoreCount = try container.decodeIfPresent(Int.self, forKey: .smallCoreCount)
        _ASICModel = try container.decodeIfPresent(String.self, forKey: ._ASICModel)
        _stratumURL = try container.decodeIfPresent(String.self, forKey: ._stratumURL)
        fallbackStratumURL = try container.decodeIfPresent(String.self, forKey: .fallbackStratumURL)
        _stratumPort = try container.decodeIfPresent(Int.self, forKey: ._stratumPort)
        fallbackStratumPort = try container.decodeIfPresent(Int.self, forKey: .fallbackStratumPort)
        _stratumUser = try container.decodeIfPresent(String.self, forKey: ._stratumUser)
        fallbackStratumUser = try container.decodeIfPresent(
            String.self,
            forKey: .fallbackStratumUser
        )
        _version = try container.decodeIfPresent(String.self, forKey: ._version)
        idfVersion = try container.decodeIfPresent(String.self, forKey: .idfVersion)
        boardVersion = try container.decodeIfPresent(String.self, forKey: .boardVersion)
        runningPartition = try container.decodeIfPresent(String.self, forKey: .runningPartition)
        flipscreen = try container.decodeIfPresent(Int.self, forKey: .flipscreen)
        overheat_mode = try container.decodeIfPresent(Int.self, forKey: .overheat_mode)
        invertscreen = try container.decodeIfPresent(Int.self, forKey: .invertscreen)
        invertfanpolarity = try container.decodeIfPresent(Int.self, forKey: .invertfanpolarity)
        autofanspeed = try container.decodeIfPresent(Int.self, forKey: .autofanspeed)
        minimumFanSpeed = Self.decodeIntFlexible(container: container, key: .minimumFanSpeed)
        fanspeed = Self.decodeIntFlexible(container: container, key: .fanspeed)
        fanrpm = try container.decodeIfPresent(Int.self, forKey: .fanrpm)

        // Decode NerdQAxe-specific fields (optional, won't affect Bitaxe)
        deviceModel = try container.decodeIfPresent(String.self, forKey: .deviceModel)
        hostip = try container.decodeIfPresent(String.self, forKey: .hostip)
        maxPower = try container.decodeIfPresent(Double.self, forKey: .maxPower)
        minPower = try container.decodeIfPresent(Double.self, forKey: .minPower)
        maxVoltage = try container.decodeIfPresent(Double.self, forKey: .maxVoltage)
        minVoltage = try container.decodeIfPresent(Double.self, forKey: .minVoltage)
        hashRateTimestamp = try container.decodeIfPresent(Int.self, forKey: .hashRateTimestamp)
        hashRate_10m = try container.decodeIfPresent(Double.self, forKey: .hashRate_10m)
        hashRate_1h = try container.decodeIfPresent(Double.self, forKey: .hashRate_1h)
        hashRate_1d = try container.decodeIfPresent(Double.self, forKey: .hashRate_1d)
        jobInterval = try container.decodeIfPresent(Int.self, forKey: .jobInterval)
        overheat_temp = try container.decodeIfPresent(Double.self, forKey: .overheat_temp)
        autoscreenoff = try container.decodeIfPresent(Int.self, forKey: .autoscreenoff)
        lastResetReason = try container.decodeIfPresent(String.self, forKey: .lastResetReason)
        stratum = try container.decodeIfPresent(StratumInfoDTO.self, forKey: .stratum)

        // Handle hashRate variants - try the main key first, then NerdQAxe/Bitaxe fallbacks
        if let hr = try? container.decode(Double.self, forKey: .hashRate) {
            hashRate = hr
        } else {
            // Try NerdQAxe hashrate variants first (most recent data)
            if let hr = try? container.decode(Double.self, forKey: .hashRate_10m) {
                hashRate = hr
            } else if let hr = try? container.decode(Double.self, forKey: .hashRate_1h) {
                hashRate = hr
            } else {
                // Fall back to original Bitaxe logic for backward compatibility
                let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
                if let hr = try? dynamicContainer.decode(
                    Double.self,
                    forKey: DynamicCodingKey(stringValue: "hashrate")
                ) {
                    hashRate = hr
                } else {
                    hashRate = nil
                }
            }
        }
    }
}

struct StratumInfoDTO: Codable {
    let poolMode: Int?
    let activePoolMode: Int?
    let poolBalance: Int?
    let usingFallback: Bool?
}

enum DeviceType {
    case bitaxe
    case nerdqaxe
    case unknown
}

extension SystemInfoDTO {
    // Canonical hashrate in GH/s (handles some firmware reporting MH/s in `hashRate`).
    var hashrate: Double? {
        guard let raw = hashRate else { return nil }
        // For Bitaxe-class devices the hashrate should be in the hundreds/thousands of GH/s.
        // If a device reports a value this large, it's almost certainly MH/s and needs /1000.
        if raw >= 50_000 {
            return raw / 1_000.0
        }
        return raw
    }
    var temperature: Double? { temp }
    var fanPercent: Int? { fanspeed }
    var mac: String? { macAddr }
    var poolUser: String? { stratumUser }
    var poolURL: String? { poolDisplayName }
    var wifiSSID: String? { ssid }
    var ip: String? { nil }
    var status: String? { "ok" }
    var uptime: UInt64? { UInt64(uptimeSeconds ?? 0) }

    // Device type detection for future device-specific features
    var deviceType: DeviceType {
        if let model = deviceModel, model.lowercased().contains("nerd") {
            return .nerdqaxe
        } else if hostname.lowercased().contains("nerd") {
            return .nerdqaxe
        } else if hostname.lowercased().contains("axe") || ASICModel.contains("BM") {
            return .bitaxe
        } else {
            return .unknown
        }
    }

    // Computed properties with fallbacks - maintains API compatibility
    var hostname: String { _hostname ?? "Unknown Miner" }
    var version: String { _version ?? "Unknown" }
    var ASICModel: String { _ASICModel ?? "Unknown" }
    var bestDiff: String { _bestDiff ?? "0" }
    var stratumURL: String { _stratumURL ?? "" }
    var stratumUser: String { _stratumUser ?? "" }
    var stratumPort: Int { _stratumPort ?? 0 }
    var poolDisplayName: String? {
        let primary = stratumURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondary = fallbackStratumURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isUsingFallback = (isUsingFallbackStratum == 1) || (stratum?.usingFallback == true)
        let isDualPool = (stratum?.poolMode ?? stratum?.activePoolMode ?? 0) == 1

        if isDualPool {
            guard !primary.isEmpty || !secondary.isEmpty else { return nil }
            if primary.isEmpty { return secondary }
            if secondary.isEmpty { return primary }
            let balance = max(0, min(100, stratum?.poolBalance ?? 50))
            let secondaryBalance = max(0, 100 - balance)
            return "\(primary) (\(balance)%) • \(secondary) (\(secondaryBalance)%)"
        }

        if isUsingFallback, !secondary.isEmpty {
            return secondary
        }

        return primary.isEmpty ? (secondary.isEmpty ? nil : secondary) : primary
    }
}

struct ErrorDTO: Codable {
    let error: String
    let message: String?
}

// AxeOS 2.11.0 switched bestDiff/bestSessionDiff from string to number.
// Decode both string and numeric payloads and normalize everything to a string.
// Prefer integers first to avoid appending ".0" and to preserve precision.
extension SystemInfoDTO {
    fileprivate static func decodeDiffAsString(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> String? {
        if let int64Value = try? container.decode(Int64.self, forKey: key) {
            return String(int64Value)
        }
        if let doubleValue = try? container.decode(Double.self, forKey: key) {
            return String(doubleValue)
        }
        if let stringValue = try? container.decode(String.self, forKey: key) {
            return stringValue
        }
        return nil
    }

    // Some firmware builds emit fan speed as Double; accept either and normalize to Int.
    fileprivate static func decodeIntFlexible(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Int? {
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: key) {
            return intValue
        }
        if let doubleValue = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Int(doubleValue)
        }
        return nil
    }

    // Some firmware builds emit numeric fields as strings; accept both.
    fileprivate static func decodeDoubleFlexible(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Double? {
        if let doubleValue = try? container.decodeIfPresent(Double.self, forKey: key) {
            return doubleValue
        }
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: key) {
            return Double(intValue)
        }
        if let stringValue = try? container.decodeIfPresent(String.self, forKey: key) {
            return Double(stringValue)
        }
        return nil
    }
}
