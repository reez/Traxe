import Foundation

// MARK: - /api/system/info Response DTO

struct SystemInfoDTO: Codable {
    // Core metrics
    let power: Double
    let voltage: Double
    let current: Double
    let temp: Int
    let vrTemp: Int
    let hashRate: Double
    let bestDiff: String
    let bestSessionDiff: String
    let stratumDiff: Int

    // System info
    let isUsingFallbackStratum: Int
    let freeHeap: Int
    let coreVoltage: Int
    let coreVoltageActual: Int
    let frequency: Int

    // Network info
    let ssid: String
    let macAddr: String
    let hostname: String
    let wifiStatus: String

    // Mining stats
    let sharesAccepted: Int
    let sharesRejected: Int
    let uptimeSeconds: Int

    // Hardware info
    let asicCount: Int
    let smallCoreCount: Int
    let ASICModel: String

    // Pool config
    let stratumURL: String
    let fallbackStratumURL: String
    let stratumPort: Int
    let fallbackStratumPort: Int
    let stratumUser: String
    let fallbackStratumUser: String

    // Version info
    let version: String
    let idfVersion: String
    let boardVersion: String
    let runningPartition: String

    // Display/Fan settings
    let flipscreen: Int
    let overheat_mode: Int
    let invertscreen: Int
    let invertfanpolarity: Int
    let autofanspeed: Int
    let fanspeed: Int
    let fanrpm: Int

    enum CodingKeys: String, CodingKey {
        case power, voltage, current, temp, vrTemp
        case hashRate = "hashRate"
        case bestDiff, bestSessionDiff, stratumDiff
        case isUsingFallbackStratum, freeHeap
        case coreVoltage, coreVoltageActual, frequency
        case ssid, macAddr, hostname, wifiStatus
        case sharesAccepted, sharesRejected, uptimeSeconds
        case asicCount, smallCoreCount
        case ASICModel = "ASICModel"
        case stratumURL, fallbackStratumURL
        case stratumPort, fallbackStratumPort
        case stratumUser, fallbackStratumUser
        case version, idfVersion, boardVersion
        case runningPartition
        case flipscreen, overheat_mode
        case invertscreen, invertfanpolarity
        case autofanspeed, fanspeed, fanrpm
    }
}

extension SystemInfoDTO {
    var hashrate: Double? { hashRate }
    var temperature: Double? { Double(temp) }
    var fanPercent: Int? { fanspeed }
    var mac: String? { macAddr }
    var poolUser: String? { stratumUser }
    var poolURL: String? { stratumURL }
    var wifiSSID: String? { ssid }
    var wifiRSSI: Int? { 0 }
    var ip: String? { nil }
    var status: String? { "ok" }
    var uptime: UInt64? { UInt64(uptimeSeconds) }
}

struct ErrorDTO: Codable {
    let error: String
    let message: String?
}
