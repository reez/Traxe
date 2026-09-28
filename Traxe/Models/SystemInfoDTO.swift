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

struct HashrateMonitorDTO: Codable {
    let asics: [HashrateMonitorASICDTO]?
}

struct HashrateMonitorASICDTO: Codable {
    let total: Double?
    let domains: [Double]?
}

// ESP-Miner v2.15.0 stopped registering the flat `stratum*` write properties and takes a
// `pools` array instead. Any pool property missing from a PATCH body is written back with a
// firmware default, so untouched properties must be echoed exactly as the miner reported
// them, including their JSON value type.
// https://github.com/bitaxeorg/ESP-Miner/blob/v2.15.0/main/http_server/http_server.c#L730-L828
enum FirmwareJSONValue: Codable, Equatable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case array([FirmwareJSONValue])
    case object([String: FirmwareJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([FirmwareJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: FirmwareJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    // Firmware may report the same whole number as an integer or as a double.
    func isEquivalent(to other: FirmwareJSONValue) -> Bool {
        switch (self, other) {
        case (.int(let lhs), .double(let rhs)): return Double(lhs) == rhs
        case (.double(let lhs), .int(let rhs)): return lhs == Double(rhs)
        default: return self == other
        }
    }
}

// One entry of the ESP-Miner v2.15 `pools` array. The complete firmware object is kept so it
// can be round-tripped without dropping properties Traxe does not edit.
struct MinerPoolDTO: Codable, Equatable {
    static let idKey = "id"
    static let stratumURLKey = "stratumURL"
    static let stratumPortKey = "stratumPort"
    static let stratumUserKey = "stratumUser"
    static let stratumPasswordKey = "stratumPassword"
    static let stratumProtocolKey = "stratumProtocol"
    static let stratumV2ChannelTypeKey = "stratumV2ChannelType"
    static let stratumV2AuthorityPubkeyKey = "stratumV2AuthorityPubkey"

    var properties: [String: FirmwareJSONValue]

    // Pool slot IDs are assigned by the miner and are not guaranteed to be 0 and 1.
    var id: Int? { int(forKey: Self.idKey) }
    var stratumURL: String? { string(forKey: Self.stratumURLKey) }
    var stratumPort: Int? { int(forKey: Self.stratumPortKey) }
    var stratumUser: String? { string(forKey: Self.stratumUserKey) }
    // ESP-Miner masks a stored password as "*****" in GET responses and keeps the stored
    // password when that mask is submitted back.
    var stratumPassword: String? { string(forKey: Self.stratumPasswordKey) }
    var stratumProtocol: String? { string(forKey: Self.stratumProtocolKey) }
    var stratumV2ChannelType: String? { string(forKey: Self.stratumV2ChannelTypeKey) }
    var stratumV2AuthorityPubkey: String? { string(forKey: Self.stratumV2AuthorityPubkeyKey) }

    init(properties: [String: FirmwareJSONValue]) {
        self.properties = properties
    }

    init(from decoder: Decoder) throws {
        properties = try [String: FirmwareJSONValue](from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try properties.encode(to: encoder)
    }

    private func string(forKey key: String) -> String? {
        guard case .string(let value) = properties[key] else { return nil }
        return value
    }

    private func int(forKey key: String) -> Int? {
        switch properties[key] {
        case .int(let value): return value
        case .double(let value): return Int(exactly: value.rounded(.towardZero))
        default: return nil
        }
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
    let errorPercentage: Double?
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
    let miningPaused: Bool?
    let hashrateMonitor: HashrateMonitorDTO?

    let asicCount: Int?
    let smallCoreCount: Int?
    let _ASICModel: String?

    let _stratumURL: String?
    let fallbackStratumURL: String?
    let _stratumPort: Int?
    let fallbackStratumPort: Int?
    let _stratumUser: String?
    let fallbackStratumUser: String?
    let stratumProtocol: String?
    let fallbackStratumProtocol: String?
    let stratumV2ChannelType: String?
    let fallbackStratumV2ChannelType: String?
    let stratumV2AuthorityPubkey: String?
    let fallbackStratumV2AuthorityPubkey: String?

    // ESP-Miner v2.15 pool API (additive; the flat properties above are still reported).
    let pools: [MinerPoolDTO]?
    let primaryPoolIndex: Int?
    let secondaryPoolIndex: Int?
    let useFallbackStratum: Bool?

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
        case expectedHashrate, errorPercentage
        case _bestDiff = "bestDiff"
        case bestSessionDiff, stratumDiff
        case isUsingFallbackStratum, freeHeap
        case coreVoltage, coreVoltageActual, frequency
        case ssid, macAddr
        case _hostname = "hostname"
        case wifiStatus, wifiRSSI
        case sharesAccepted, sharesRejected, uptimeSeconds
        case blockHeight, networkDifficulty, blockFound, miningPaused
        case hashrateMonitor
        case asicCount, smallCoreCount
        case _ASICModel = "ASICModel"
        case _stratumURL = "stratumURL"
        case fallbackStratumURL
        case _stratumPort = "stratumPort"
        case fallbackStratumPort
        case _stratumUser = "stratumUser"
        case fallbackStratumUser
        case stratumProtocol, fallbackStratumProtocol
        case stratumV2ChannelType, fallbackStratumV2ChannelType
        case stratumV2AuthorityPubkey, fallbackStratumV2AuthorityPubkey
        case pools, primaryPoolIndex, secondaryPoolIndex, useFallbackStratum
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
        power = try Self.decodeFiniteDouble(container: container, key: .power)
        voltage = try Self.decodeFiniteDouble(container: container, key: .voltage)
        current = try Self.decodeFiniteDouble(container: container, key: .current)
        temp = try Self.decodeFiniteDouble(container: container, key: .temp)
        // Handle vrTemp - support both Int (Bitaxe) and Double (NerdQAxe)
        if let doubleValue = try? container.decode(Double.self, forKey: .vrTemp),
            doubleValue.isFinite
        {
            vrTemp = doubleValue
        } else if let intValue = try? container.decode(Int.self, forKey: .vrTemp) {
            vrTemp = Double(intValue)
        } else {
            vrTemp = nil
        }
        expectedHashrate = try Self.decodeFiniteDouble(container: container, key: .expectedHashrate)
        errorPercentage = Self.decodeDoubleFlexible(container: container, key: .errorPercentage)
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
        miningPaused = Self.decodeBoolFlexible(container: container, key: .miningPaused)
        hashrateMonitor = try container.decodeIfPresent(
            HashrateMonitorDTO.self,
            forKey: .hashrateMonitor
        )
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
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        stratumProtocol = Self.decodeStratumProtocol(
            container: container,
            key: .stratumProtocol
        )
        fallbackStratumProtocol = Self.decodeStratumProtocol(
            container: container,
            key: .fallbackStratumProtocol
        )
        stratumV2ChannelType =
            Self.decodeSV2ChannelType(container: container, key: .stratumV2ChannelType)
            ?? Self.decodeSV2ChannelType(
                container: dynamicContainer,
                key: DynamicCodingKey(stringValue: "sv2ChannelType")
            )
        fallbackStratumV2ChannelType =
            Self.decodeSV2ChannelType(container: container, key: .fallbackStratumV2ChannelType)
            ?? Self.decodeSV2ChannelType(
                container: dynamicContainer,
                key: DynamicCodingKey(stringValue: "fallbackSv2ChannelType")
            )
        stratumV2AuthorityPubkey =
            try container.decodeIfPresent(String.self, forKey: .stratumV2AuthorityPubkey)
            ?? dynamicContainer.decodeIfPresent(
                String.self,
                forKey: DynamicCodingKey(stringValue: "sv2AuthorityPubkey")
            )
        fallbackStratumV2AuthorityPubkey =
            try container.decodeIfPresent(String.self, forKey: .fallbackStratumV2AuthorityPubkey)
            ?? dynamicContainer.decodeIfPresent(
                String.self,
                forKey: DynamicCodingKey(stringValue: "fallbackSv2AuthorityPubkey")
            )
        pools = try container.decodeIfPresent([MinerPoolDTO].self, forKey: .pools)
        primaryPoolIndex = try container.decodeIfPresent(Int.self, forKey: .primaryPoolIndex)
        secondaryPoolIndex = try container.decodeIfPresent(Int.self, forKey: .secondaryPoolIndex)
        useFallbackStratum = Self.decodeBoolFlexible(container: container, key: .useFallbackStratum)
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
        maxPower = try Self.decodeFiniteDouble(container: container, key: .maxPower)
        minPower = try Self.decodeFiniteDouble(container: container, key: .minPower)
        maxVoltage = try Self.decodeFiniteDouble(container: container, key: .maxVoltage)
        minVoltage = try Self.decodeFiniteDouble(container: container, key: .minVoltage)
        hashRateTimestamp = try container.decodeIfPresent(Int.self, forKey: .hashRateTimestamp)
        hashRate_10m = try Self.decodeFiniteDouble(container: container, key: .hashRate_10m)
        hashRate_1h = try Self.decodeFiniteDouble(container: container, key: .hashRate_1h)
        hashRate_1d = try Self.decodeFiniteDouble(container: container, key: .hashRate_1d)
        jobInterval = try container.decodeIfPresent(Int.self, forKey: .jobInterval)
        overheat_temp = try Self.decodeFiniteDouble(container: container, key: .overheat_temp)
        autoscreenoff = try container.decodeIfPresent(Int.self, forKey: .autoscreenoff)
        lastResetReason = try container.decodeIfPresent(String.self, forKey: .lastResetReason)
        stratum = try container.decodeIfPresent(StratumInfoDTO.self, forKey: .stratum)

        // Handle hashRate variants - try the main key first, then NerdQAxe/Bitaxe fallbacks
        if let hr = try? container.decode(Double.self, forKey: .hashRate), hr.isFinite {
            hashRate = hr
        } else {
            // Try NerdQAxe hashrate variants first (most recent data)
            if let hr = try? container.decode(Double.self, forKey: .hashRate_10m), hr.isFinite {
                hashRate = hr
            } else if let hr = try? container.decode(Double.self, forKey: .hashRate_1h), hr.isFinite
            {
                hashRate = hr
            } else {
                // Fall back to original Bitaxe logic for backward compatibility
                if let hr = try? dynamicContainer.decode(
                    Double.self,
                    forKey: DynamicCodingKey(stringValue: "hashrate")
                ), hr.isFinite {
                    hashRate = hr
                } else {
                    hashRate = nil
                }
            }
        }
    }
}

struct MinerTelemetryDTO: Decodable {
    let power: Double?
    let voltage: Double?
    let current: Double?
    let temp: Double?
    let vrTemp: Double?
    let hashRate: Double?
    let expectedHashrate: Double?
    let errorPercentage: Double?
    let _bestDiff: String?
    let bestSessionDiff: String?
    let isUsingFallbackStratum: Int?
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
    let miningPaused: Bool?
    let hashrateMonitor: HashrateMonitorDTO?
    let asicCount: Int?
    let smallCoreCount: Int?
    let _ASICModel: String?
    let _stratumURL: String?
    let fallbackStratumURL: String?
    let _stratumUser: String?
    let fallbackStratumUser: String?
    let _version: String?
    let idfVersion: String?
    let boardVersion: String?
    let runningPartition: String?
    let fanspeed: Int?
    let fanrpm: Int?
    let deviceModel: String?
    let hostip: String?
    let hashRateTimestamp: Int?
    let hashRate_10m: Double?
    let hashRate_1h: Double?
    let hashRate_1d: Double?
    let stratum: StratumInfoDTO?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)

        power = Self.decodeDouble(container: container, key: "power")
        voltage = Self.decodeDouble(container: container, key: "voltage")
        current = Self.decodeDouble(container: container, key: "current")
        temp = Self.decodeDouble(container: container, key: "temp")
        vrTemp = Self.decodeDouble(container: container, key: "vrTemp")
        expectedHashrate = Self.decodeDouble(container: container, key: "expectedHashrate")
        errorPercentage = Self.decodeDouble(container: container, key: "errorPercentage")
        _bestDiff = Self.decodeDiffAsString(container: container, key: "bestDiff")
        bestSessionDiff = Self.decodeDiffAsString(container: container, key: "bestSessionDiff")
        isUsingFallbackStratum = Self.decodeFallbackStratum(container: container)
        coreVoltage = Self.decodeInt(container: container, key: "coreVoltage")
        coreVoltageActual = Self.decodeInt(container: container, key: "coreVoltageActual")
        frequency = Self.decodeInt(container: container, key: "frequency")
        ssid = Self.decodeString(container: container, key: "ssid")
        macAddr = Self.decodeString(container: container, key: "macAddr")
        _hostname = Self.decodeString(container: container, key: "hostname")
        wifiStatus = Self.decodeString(container: container, key: "wifiStatus")
        wifiRSSI = Self.decodeInt(container: container, key: "wifiRSSI")
        sharesAccepted = Self.decodeInt(container: container, key: "sharesAccepted")
        sharesRejected = Self.decodeInt(container: container, key: "sharesRejected")
        uptimeSeconds = Self.decodeInt(container: container, key: "uptimeSeconds")
        blockHeight = Self.decodeInt(container: container, key: "blockHeight")
        networkDifficulty = Self.decodeDouble(container: container, key: "networkDifficulty")
        blockFound = Self.decodeBlockFound(container: container)
        miningPaused = Self.decodeBool(container: container, key: "miningPaused")
        hashrateMonitor = try? container.decodeIfPresent(
            HashrateMonitorDTO.self,
            forKey: Self.key("hashrateMonitor")
        )
        asicCount = Self.decodeInt(container: container, key: "asicCount")
        smallCoreCount = Self.decodeInt(container: container, key: "smallCoreCount")
        _ASICModel = Self.decodeString(container: container, key: "ASICModel")
        _stratumURL = Self.decodeString(container: container, key: "stratumURL")
        fallbackStratumURL = Self.decodeString(container: container, key: "fallbackStratumURL")
        _stratumUser = Self.decodeString(container: container, key: "stratumUser")
        fallbackStratumUser = Self.decodeString(container: container, key: "fallbackStratumUser")
        _version = Self.decodeString(container: container, key: "version")
        idfVersion = Self.decodeString(container: container, key: "idfVersion")
        boardVersion = Self.decodeString(container: container, key: "boardVersion")
        runningPartition = Self.decodeString(container: container, key: "runningPartition")
        fanspeed = Self.decodeInt(container: container, key: "fanspeed")
        fanrpm = Self.decodeInt(container: container, key: "fanrpm")
        deviceModel = Self.decodeString(container: container, key: "deviceModel")
        hostip = Self.decodeString(container: container, key: "hostip")
        hashRateTimestamp = Self.decodeInt(container: container, key: "hashRateTimestamp")
        hashRate_10m = Self.decodeDouble(container: container, key: "hashRate_10m")
        hashRate_1h = Self.decodeDouble(container: container, key: "hashRate_1h")
        hashRate_1d = Self.decodeDouble(container: container, key: "hashRate_1d")
        stratum = try? container.decodeIfPresent(StratumInfoDTO.self, forKey: Self.key("stratum"))

        hashRate =
            Self.decodeDouble(container: container, key: "hashRate")
            ?? hashRate_10m
            ?? hashRate_1h
            ?? Self.decodeDouble(container: container, key: "hashrate")
    }
}

extension MinerTelemetryDTO {
    var hashrate: Double? {
        guard let raw = hashRate else { return nil }
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
    var uptime: UInt64? { UInt64(uptimeSeconds ?? 0) }
    var hostname: String { Self.displayString(_hostname) ?? "Unknown Miner" }
    var version: String { Self.displayString(_version) ?? "Unknown" }
    var ASICModel: String { Self.displayString(_ASICModel) ?? "Unknown" }
    var bestDiff: String { _bestDiff ?? "0" }
    var stratumURL: String { _stratumURL ?? "" }
    var stratumUser: String { _stratumUser ?? "" }

    var deviceType: DeviceType {
        let model = Self.identityString(deviceModel)?.lowercased() ?? ""
        let hostname = Self.identityString(_hostname)?.lowercased() ?? ""
        let asicModel = Self.identityString(_ASICModel)?.uppercased() ?? ""

        if model.contains("nerd") {
            return .nerdqaxe
        } else if hostname.contains("nerd") {
            return .nerdqaxe
        } else if hostname.contains("axe") || model.contains("axe") || asicModel.contains("BM") {
            return .bitaxe
        } else {
            return .unknown
        }
    }

    var isCompatibleMiner: Bool {
        let lowercasedHostname = Self.identityString(_hostname)?.lowercased() ?? ""
        let lowercasedVersion = Self.identityString(_version)?.lowercased() ?? ""
        let lowercasedDeviceModel = Self.identityString(deviceModel)?.lowercased() ?? ""
        let uppercasedASICModel = Self.identityString(_ASICModel)?.uppercased() ?? ""

        guard !lowercasedHostname.isEmpty || !lowercasedVersion.isEmpty
            || !lowercasedDeviceModel.isEmpty || !uppercasedASICModel.isEmpty
        else {
            return false
        }

        return lowercasedHostname.contains("axe")
            || lowercasedVersion.contains("axe")
            || lowercasedDeviceModel.contains("axe")
            || lowercasedHostname.contains("nerd")
            || lowercasedDeviceModel.contains("nerd")
            || lowercasedHostname.contains("esp-miner")
            || lowercasedVersion.contains("esp-miner")
            || lowercasedHostname.contains("miner")
            || lowercasedVersion.contains("miner")
            || lowercasedHostname.contains("lucky")
            || lowercasedDeviceModel.contains("lucky")
            || lowercasedHostname.contains("lv")
            || lowercasedDeviceModel.contains("lv")
            || lowercasedHostname.contains("qaxe")
            || lowercasedDeviceModel.contains("qaxe")
            || uppercasedASICModel == "BM1366"
            || uppercasedASICModel == "BM1368"
            || (uppercasedASICModel.contains("BM")
                && uppercasedASICModel.rangeOfCharacter(from: .decimalDigits) != nil)
            || uppercasedASICModel == "LV07"
            || uppercasedASICModel == "LV08"
            || (uppercasedASICModel.contains("LV")
                && uppercasedASICModel.rangeOfCharacter(from: .decimalDigits) != nil)
    }

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

extension MinerTelemetryDTO {
    private static func displayString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func identityString(_ value: String?) -> String? {
        guard let trimmed = displayString(value) else { return nil }
        switch trimmed.lowercased() {
        case "unknown", "unknown miner":
            return nil
        default:
            return trimmed
        }
    }

    private static func key(_ stringValue: String) -> DynamicCodingKey {
        DynamicCodingKey(stringValue: stringValue)
    }

    private static func decodeString(
        container: KeyedDecodingContainer<DynamicCodingKey>,
        key: String
    ) -> String? {
        try? container.decodeIfPresent(String.self, forKey: Self.key(key))
    }

    private static func decodeInt(
        container: KeyedDecodingContainer<DynamicCodingKey>,
        key: String
    ) -> Int? {
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: Self.key(key)) {
            return intValue
        }
        if let doubleValue = try? container.decodeIfPresent(Double.self, forKey: Self.key(key)) {
            return Int(exactly: doubleValue.rounded(.towardZero))
        }
        if let stringValue = try? container.decodeIfPresent(String.self, forKey: Self.key(key)) {
            return Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func decodeDouble(
        container: KeyedDecodingContainer<DynamicCodingKey>,
        key: String
    ) -> Double? {
        if let doubleValue = try? container.decodeIfPresent(Double.self, forKey: Self.key(key)) {
            return doubleValue.isFinite ? doubleValue : nil
        }
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: Self.key(key)) {
            return Double(intValue)
        }
        if let stringValue = try? container.decodeIfPresent(String.self, forKey: Self.key(key)) {
            guard let value = Double(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
                value.isFinite
            else { return nil }
            return value
        }
        return nil
    }

    private static func decodeBool(
        container: KeyedDecodingContainer<DynamicCodingKey>,
        key: String
    ) -> Bool? {
        if let boolValue = try? container.decodeIfPresent(Bool.self, forKey: Self.key(key)) {
            return boolValue
        }
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: Self.key(key)) {
            return intValue != 0
        }
        if let stringValue = try? container.decodeIfPresent(String.self, forKey: Self.key(key)) {
            switch stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private static func decodeDiffAsString(
        container: KeyedDecodingContainer<DynamicCodingKey>,
        key: String
    ) -> String? {
        if let int64Value = try? container.decodeIfPresent(Int64.self, forKey: Self.key(key)) {
            return String(int64Value)
        }
        if let doubleValue = try? container.decodeIfPresent(Double.self, forKey: Self.key(key)) {
            return String(doubleValue)
        }
        return decodeString(container: container, key: key)
    }

    private static func decodeFallbackStratum(
        container: KeyedDecodingContainer<DynamicCodingKey>
    ) -> Int? {
        if let boolValue = decodeBool(container: container, key: "isUsingFallbackStratum") {
            return boolValue ? 1 : 0
        }
        return decodeInt(container: container, key: "isUsingFallbackStratum")
    }

    private static func decodeBlockFound(
        container: KeyedDecodingContainer<DynamicCodingKey>
    ) -> Int? {
        if let boolValue = decodeBool(container: container, key: "blockFound") {
            return boolValue ? 1 : 0
        }
        return decodeInt(container: container, key: "blockFound")
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
    // ESP-Miner v2.15 serializes a `pools` array and ignores the flat pool write properties.
    // Presence of the array is the capability signal; the reported version string is not.
    var supportsMultiPoolSettings: Bool { pools != nil }
    var supportsPoolModeSettings: Bool {
        stratum?.poolMode != nil || stratum?.activePoolMode != nil
    }
    // ESP-Miner v2.15 reports the persisted `useFallbackStratum` selector in system info.
    // Earlier firmware accepts the key on PATCH but never reports it, so the selection could
    // neither be shown nor verified there.
    var supportsActivePoolSelection: Bool {
        supportsMultiPoolSettings && useFallbackStratum != nil
    }
    var primaryPoolID: Int { primaryPoolIndex ?? 0 }
    var secondaryPoolID: Int { secondaryPoolIndex ?? 1 }

    func pool(withID id: Int) -> MinerPoolDTO? {
        pools?.first { $0.id == id }
    }

    var supportsStratumProtocolSettings: Bool {
        stratumProtocol != nil ||
            fallbackStratumProtocol != nil ||
            stratumV2ChannelType != nil ||
            fallbackStratumV2ChannelType != nil ||
            stratumV2AuthorityPubkey != nil ||
            fallbackStratumV2AuthorityPubkey != nil
    }

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
    fileprivate static func decodeFiniteDouble<Key: CodingKey>(
        container: KeyedDecodingContainer<Key>,
        key: Key
    ) throws -> Double? {
        guard let value = try container.decodeIfPresent(Double.self, forKey: key), value.isFinite
        else {
            return nil
        }
        return value
    }

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
            return Int(exactly: doubleValue.rounded(.towardZero))
        }
        return nil
    }

    // NerdQAxe firmwares report Stratum protocol as 0/1; ESP-Miner reports SV1/SV2.
    fileprivate static func decodeStratumProtocol<Key: CodingKey>(
        container: KeyedDecodingContainer<Key>,
        key: Key
    ) -> String? {
        if let stringValue = try? container.decodeIfPresent(String.self, forKey: key) {
            let normalizedValue = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            switch normalizedValue {
            case "SV1", "STRATUM_V1", "0":
                return "SV1"
            case "SV2", "STRATUM_V2", "1":
                return "SV2"
            default:
                return stringValue
            }
        }
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: key) {
            switch intValue {
            case 0:
                return "SV1"
            case 1:
                return "SV2"
            default:
                return nil
            }
        }
        return nil
    }

    // NerdQAxe firmwares report SV2 channel type as 0/1; ESP-Miner reports text.
    fileprivate static func decodeSV2ChannelType<Key: CodingKey>(
        container: KeyedDecodingContainer<Key>,
        key: Key
    ) -> String? {
        if let stringValue = try? container.decodeIfPresent(String.self, forKey: key) {
            let normalizedValue = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            switch normalizedValue {
            case "extended", "0":
                return "extended"
            case "standard", "1":
                return "standard"
            default:
                return stringValue
            }
        }
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: key) {
            switch intValue {
            case 0:
                return "extended"
            case 1:
                return "standard"
            default:
                return nil
            }
        }
        return nil
    }

    // Some firmware builds emit numeric fields as strings; accept both.
    fileprivate static func decodeDoubleFlexible(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Double? {
        if let doubleValue = try? container.decodeIfPresent(Double.self, forKey: key) {
            return doubleValue.isFinite ? doubleValue : nil
        }
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: key) {
            return Double(intValue)
        }
        if let stringValue = try? container.decodeIfPresent(String.self, forKey: key) {
            guard let value = Double(stringValue), value.isFinite else { return nil }
            return value
        }
        return nil
    }

    // ESP-Miner uses booleans here; accept numeric/string variants for older or forked payloads.
    fileprivate static func decodeBoolFlexible(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Bool? {
        if let boolValue = try? container.decodeIfPresent(Bool.self, forKey: key) {
            return boolValue
        }
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: key) {
            return intValue != 0
        }
        if let stringValue = try? container.decodeIfPresent(String.self, forKey: key) {
            switch stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }
}
