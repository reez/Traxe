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

    let sharesAccepted: Int?
    let sharesRejected: Int?
    let uptimeSeconds: Int?

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
        case wifiStatus
        case sharesAccepted, sharesRejected, uptimeSeconds
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
        case autofanspeed, fanspeed, fanrpm

        // NerdQAxe-specific keys
        case deviceModel, hostip
        case maxPower, minPower
        case maxVoltage, minVoltage
        case hashRateTimestamp
        case hashRate_10m, hashRate_1h, hashRate_1d
        case jobInterval, overheat_temp
        case autoscreenoff, lastResetReason
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
        _bestDiff = try container.decodeIfPresent(String.self, forKey: ._bestDiff)
        bestSessionDiff = try container.decodeIfPresent(String.self, forKey: .bestSessionDiff)
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
        sharesAccepted = try container.decodeIfPresent(Int.self, forKey: .sharesAccepted)
        sharesRejected = try container.decodeIfPresent(Int.self, forKey: .sharesRejected)
        uptimeSeconds = try container.decodeIfPresent(Int.self, forKey: .uptimeSeconds)
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
        fanspeed = try container.decodeIfPresent(Int.self, forKey: .fanspeed)
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

enum DeviceType {
    case bitaxe
    case nerdqaxe
    case unknown
}

extension SystemInfoDTO {
    var hashrate: Double? { hashRate }
    var temperature: Double? { temp }
    var fanPercent: Int? { fanspeed }
    var mac: String? { macAddr }
    var poolUser: String? { stratumUser }
    var poolURL: String? { stratumURL }
    var wifiSSID: String? { ssid }
    var wifiRSSI: Int? { 0 }
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
    var hostname: String { _hostname ?? "Unknown Device" }
    var version: String { _version ?? "Unknown" }
    var ASICModel: String { _ASICModel ?? "Unknown" }
    var bestDiff: String { _bestDiff ?? "0" }
    var stratumURL: String { _stratumURL ?? "" }
    var stratumUser: String { _stratumUser ?? "" }
    var stratumPort: Int { _stratumPort ?? 0 }
}

struct ErrorDTO: Codable {
    let error: String
    let message: String?
}
