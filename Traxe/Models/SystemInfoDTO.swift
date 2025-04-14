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
    let vrTemp: Int?
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode all known fields as optional
        power = try container.decodeIfPresent(Double.self, forKey: .power)
        voltage = try container.decodeIfPresent(Double.self, forKey: .voltage)
        current = try container.decodeIfPresent(Double.self, forKey: .current)
        temp = try container.decodeIfPresent(Double.self, forKey: .temp)
        vrTemp = try container.decodeIfPresent(Int.self, forKey: .vrTemp)
        expectedHashrate = try container.decodeIfPresent(Double.self, forKey: .expectedHashrate)
        _bestDiff = try container.decodeIfPresent(String.self, forKey: ._bestDiff)
        bestSessionDiff = try container.decodeIfPresent(String.self, forKey: .bestSessionDiff)
        stratumDiff = try container.decodeIfPresent(Int.self, forKey: .stratumDiff)
        isUsingFallbackStratum = try container.decodeIfPresent(
            Int.self,
            forKey: .isUsingFallbackStratum
        )
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

        // Handle hashRate variants - try the main key first, then fallbacks
        if let hr = try? container.decode(Double.self, forKey: .hashRate) {
            hashRate = hr
        } else {
            // If hashRate isn't available, try hashRate_10m as fallback
            let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
            if let hr = try? dynamicContainer.decode(
                Double.self,
                forKey: DynamicCodingKey(stringValue: "hashRate_10m")
            ) {
                hashRate = hr
            } else if let hr = try? dynamicContainer.decode(
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
