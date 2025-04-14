import Foundation
import WidgetKit

struct DeviceManagementService {
    private static let session = URLSession.shared
    private static let decoder = JSONDecoder()

    static func checkDevice(ip: String) async throws -> DiscoveredDevice {
        let urlString = "http://\(ip)/api/system/info"
        guard let url = URL(string: urlString) else {
            throw DeviceCheckError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw DeviceCheckError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                do {
                    let systemInfo = try decoder.decode(SystemInfoDTO.self, from: data)
                    let lowercasedHostname = systemInfo.hostname.lowercased()
                    let lowercasedVersion = systemInfo.version.lowercased()
                    let uppercasedASICModel = systemInfo.ASICModel.uppercased()

                    let isBitaxeDevice =
                        // BitAxe variants
                        lowercasedHostname.contains("axe") || lowercasedVersion.contains("axe")
                        // NerdAxe variants (NerdAxe, NerdQAxe, NerdQAxePlus, etc.)
                        || lowercasedHostname.contains("nerd")
                        // ESP-Miner variants
                        || lowercasedHostname.contains("esp-miner") || lowercasedVersion.contains("esp-miner")
                        || lowercasedHostname.contains("miner") || lowercasedVersion.contains("miner")
                        // Lucky Miner / LVXX variants
                        || lowercasedHostname.contains("lucky") || lowercasedHostname.contains("lv")
                        // QAxe variants
                        || lowercasedHostname.contains("qaxe")
                        // ASIC model checks - BitMaker chips
                        || uppercasedASICModel == "BM1366" || uppercasedASICModel == "BM1368"
                        || (uppercasedASICModel.contains("BM")
                            && uppercasedASICModel.rangeOfCharacter(
                                from: CharacterSet.decimalDigits
                            ) != nil)
                        // ASIC model checks - Lucky Miner chips
                        || uppercasedASICModel == "LV07" || uppercasedASICModel == "LV08"
                        || (uppercasedASICModel.contains("LV")
                            && uppercasedASICModel.rangeOfCharacter(
                                from: CharacterSet.decimalDigits
                            ) != nil)

                    if isBitaxeDevice {
                        return DiscoveredDevice(
                            ip: ip,
                            name: systemInfo.hostname,
                            hashrate: systemInfo.hashrate ?? 0.0,
                            temperature: systemInfo.temperature ?? 0.0,
                            bestDiff: systemInfo.bestDiff,
                            power: systemInfo.power ?? 0.0,
                            poolURL: systemInfo.poolURL
                        )
                    } else {
                        throw DeviceCheckError.notBitaxeDevice
                    }
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
        } catch let error as URLError {
            throw DeviceCheckError.requestFailed(error.code)
        } catch let error as DeviceCheckError {
            throw error
        } catch {
            throw DeviceCheckError.unknown(error)
        }
    }

    static func saveDevice(_ deviceToSave: SavedDevice) throws {
        guard let sharedDefaults = UserDefaults(suiteName: "group.matthewramsden.traxe") else {
            throw NSError(
                domain: "DeviceSaveError",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot access shared storage."]
            )
        }

        var savedDevices: [SavedDevice] = []
        if let data = sharedDefaults.data(forKey: "savedDevices"),
            let decoded = try? JSONDecoder().decode([SavedDevice].self, from: data)
        {
            savedDevices = decoded
        }

        if !savedDevices.contains(where: { $0.ipAddress == deviceToSave.ipAddress }) {
            savedDevices.append(deviceToSave)
        } else {
            return
        }

        do {
            let encoded = try JSONEncoder().encode(savedDevices)
            sharedDefaults.set(encoded, forKey: "savedDevices")

            sharedDefaults.set(deviceToSave.ipAddress, forKey: "bitaxeIPAddress")

            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")

            WidgetCenter.shared.reloadTimelines(ofKind: "TraxeWidget")
        } catch {
            throw error
        }
    }

    static func deleteDevice(ipAddressToDelete: String) throws {
        guard let sharedDefaults = UserDefaults(suiteName: "group.matthewramsden.traxe") else {
            throw NSError(
                domain: "DeviceDeleteError",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot access shared storage."]
            )
        }

        var savedDevices: [SavedDevice] = []
        if let data = sharedDefaults.data(forKey: "savedDevices"),
            let decoded = try? JSONDecoder().decode([SavedDevice].self, from: data)
        {
            savedDevices = decoded
        }

        let initialCount = savedDevices.count
        savedDevices.removeAll { $0.ipAddress == ipAddressToDelete }

        guard savedDevices.count < initialCount else {
            return
        }

        do {
            let encoded = try JSONEncoder().encode(savedDevices)
            sharedDefaults.set(encoded, forKey: "savedDevices")

            if let currentIP = sharedDefaults.string(forKey: "bitaxeIPAddress"),
                currentIP == ipAddressToDelete
            {
                sharedDefaults.removeObject(forKey: "bitaxeIPAddress")
            }

            WidgetCenter.shared.reloadTimelines(ofKind: "TraxeWidget")

        } catch {
            throw error
        }
    }

    static func reorderDevices(_ devices: [SavedDevice]) throws {
        guard let sharedDefaults = UserDefaults(suiteName: "group.matthewramsden.traxe") else {
            throw NSError(
                domain: "DeviceReorderError",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot access shared storage."]
            )
        }

        do {
            let encoded = try JSONEncoder().encode(devices)
            sharedDefaults.set(encoded, forKey: "savedDevices")

            let ipAddresses = devices.map { $0.ipAddress }
            sharedDefaults.set(ipAddresses, forKey: "savedDeviceIPs")

            WidgetCenter.shared.reloadTimelines(ofKind: "TraxeWidget")
        } catch {
            throw error
        }
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
        case .invalidURL: return "Internal error: Could not create URL for device check."
        case .requestFailed(let code):
            switch code {
            case .timedOut:
                return "The request timed out. The device might be offline or unreachable."
            case .cannotConnectToHost:
                return
                    "Cannot connect to the device. Ensure it's powered on and on the same network."
            case .notConnectedToInternet:
                return "Please check your network connection."
            case .networkConnectionLost:
                return "The network connection was lost."
            default:
                return "A network error occurred (Code: \(code.rawValue))."
            }
        case .invalidResponse: return "Received invalid response from the device IP."
        case .decodingError(let field, let swiftError, _):
            var baseMessage = "Could not understand the response from the device"
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
            return "The device at this IP address doesn't appear to be a compatible."
        case .unknown(let error): return "An unknown error occurred: \(error.localizedDescription)"
        }
    }
}
