import Foundation

struct SystemInfoDTO: Codable {
    let power: Double?
    let voltage: Double?
    let current: Double?
    let temp: Double?
    let vrTemp: Int?
    let hashRate: Double?
    let expectedHashrate: Double?
    let bestDiff: String
    let bestSessionDiff: String?
    let stratumDiff: Int?

    let isUsingFallbackStratum: Int?
    let freeHeap: Int?
    let coreVoltage: Int?
    let coreVoltageActual: Int?
    let frequency: Int?

    let ssid: String?
    let macAddr: String?
    let hostname: String
    let wifiStatus: String?

    let sharesAccepted: Int?
    let sharesRejected: Int?
    let uptimeSeconds: Int?

    let asicCount: Int?
    let smallCoreCount: Int?
    let ASICModel: String

    let stratumURL: String
    let fallbackStratumURL: String?
    let stratumPort: Int
    let fallbackStratumPort: Int?
    let stratumUser: String
    let fallbackStratumUser: String?

    let version: String
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

    enum CodingKeys: String, CodingKey {
        case power, voltage, current, temp, vrTemp
        case hashRate = "hashRate"
        case expectedHashrate
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
}

struct ErrorDTO: Codable {
    let error: String
    let message: String?
}
