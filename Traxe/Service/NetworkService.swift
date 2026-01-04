import Foundation

actor NetworkService {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    private func getBaseURL(for ipAddressOverride: String? = nil) -> URL? {
        let suiteName = "group.matthewramsden.traxe"
        var targetIP: String? = nil

        if let override = ipAddressOverride, !override.isEmpty {
            targetIP = override
        } else {
            guard let sharedDefaults = UserDefaults(suiteName: suiteName) else {
                return nil
            }
            targetIP = sharedDefaults.string(forKey: "bitaxeIPAddress")
        }

        guard let ipAddress = targetIP, !ipAddress.isEmpty else {
            return nil
        }

        let cleanIP = ipAddress.replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "/", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let ipRegex =
            #"^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"#
        guard cleanIP.range(of: ipRegex, options: .regularExpression) != nil else {
            return nil
        }

        guard let url = URL(string: "http://\(cleanIP)") else {
            return nil
        }
        return url
    }

    func performGET<T: Codable>(endpoint: String, ipAddressOverride: String? = nil) async throws
        -> T
    {
        guard let baseURL = getBaseURL(for: ipAddressOverride) else {
            throw NetworkError.configurationMissing
        }
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                do {
                    return try decoder.decode(T.self, from: data)
                } catch {
                    throw NetworkError.decodingError(error, jsonData: data)
                }
            case 404:
                throw NetworkError.apiError(message: "Miner not found at the specified IP address")
            case 500:
                throw NetworkError.apiError(message: "Miner server error")
            default:
                throw NetworkError.apiError(
                    message: "Unexpected response: \(httpResponse.statusCode)"
                )
            }
        } catch let error as NetworkError {
            throw error
        } catch {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet, .cannotConnectToHost, .timedOut:
                    throw NetworkError.requestFailed(error)
                default:
                    throw NetworkError.requestFailed(error)
                }
            }
            throw NetworkError.unknown
        }
    }

    func fetchSystemInfo(ipAddressOverride: String? = nil) async throws -> SystemInfoDTO {
        try await performGET(endpoint: "/api/system/info", ipAddressOverride: ipAddressOverride)
    }

    func fetchSwarmInfo(ipAddressOverride: String? = nil) async throws -> /* SwarmInfoDTO */
    Codable {
        struct PlaceholderSwarmDTO: Codable { var message: String = "Swarm info placeholder" }
        return try await performGET(
            endpoint: "/api/swarm/info",
            ipAddressOverride: ipAddressOverride
        ) as PlaceholderSwarmDTO
    }

    func performPOST(endpoint: String, ipAddressOverride: String? = nil) async throws {
        guard let baseURL = getBaseURL(for: ipAddressOverride) else {
            throw NetworkError.configurationMissing
        }
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30.0

        do {
            let (_, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200, 202:
                return
            case 404:
                throw NetworkError.apiError(message: "Endpoint not found")
            case 500:
                throw NetworkError.apiError(message: "Miner server error")
            default:
                throw NetworkError.apiError(
                    message: "Unexpected response: \(httpResponse.statusCode)"
                )
            }
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.requestFailed(error)
        }
    }

    func updateFirmware(ipAddressOverride: String? = nil) async throws {
        try await performPOST(endpoint: "/api/system/OTA", ipAddressOverride: ipAddressOverride)
    }

    func restartDevice(ipAddressOverride: String? = nil) async throws {
        try await performPOST(endpoint: "/api/system/restart", ipAddressOverride: ipAddressOverride)
    }

    private func performPATCH<T: Encodable>(
        endpoint: String,
        body: T,
        ipAddressOverride: String? = nil
    ) async throws {
        guard let baseURL = getBaseURL(for: ipAddressOverride) else {
            throw NetworkError.configurationMissing
        }
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5.0

        let encoder = JSONEncoder()
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw error
        }

        do {
            let (_, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200, 202:
                return
            case 404:
                throw NetworkError.apiError(message: "Endpoint not found")
            case 500:
                throw NetworkError.apiError(message: "Miner server error")
            default:
                throw NetworkError.apiError(
                    message: "Unexpected response: \(httpResponse.statusCode)"
                )
            }
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.requestFailed(error)
        }
    }

    func updateSystemSettings(
        fanspeed: Int? = nil,
        autofanspeed: Int? = nil,
        stratumUser: String? = nil,
        stratumURL: String? = nil,
        stratumPort: Int? = nil,
        fallbackStratumUser: String? = nil,
        fallbackStratumURL: String? = nil,
        fallbackStratumPort: Int? = nil,
        poolBalance: Int? = nil,
        poolMode: Int? = nil,
        hostname: String? = nil,
        ipAddressOverride: String? = nil
    ) async throws {
        struct SystemSettingsUpdate: Encodable {
            let fanspeed: Int?
            let autofanspeed: Int?
            let stratumUser: String?
            let stratumURL: String?
            let stratumPort: Int?
            let fallbackStratumUser: String?
            let fallbackStratumURL: String?
            let fallbackStratumPort: Int?
            let poolBalance: Int?
            let poolMode: Int?
            let hostname: String?
        }

        let update = SystemSettingsUpdate(
            fanspeed: fanspeed,
            autofanspeed: autofanspeed,
            stratumUser: stratumUser,
            stratumURL: stratumURL,
            stratumPort: stratumPort,
            fallbackStratumUser: fallbackStratumUser,
            fallbackStratumURL: fallbackStratumURL,
            fallbackStratumPort: fallbackStratumPort,
            poolBalance: poolBalance,
            poolMode: poolMode,
            hostname: hostname
        )
        try await performPATCH(
            endpoint: "/api/system",
            body: update,
            ipAddressOverride: ipAddressOverride
        )
    }
}

enum NetworkError: Error, LocalizedError {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse
    case decodingError(Error, jsonData: Data?)
    case apiError(message: String)
    case unknown
    case configurationMissing

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "The miner IP address appears to be invalid."
        case .requestFailed(let error):
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet:
                    return "Not connected to the internet. Please check your connection."
                case .cannotConnectToHost:
                    return
                        "Cannot connect to the miner. Ensure it's powered on and on the same network."
                case .timedOut:
                    return "The request timed out. The miner might be busy or unreachable."
                default: return "Network request failed: \(urlError.localizedDescription)"
                }
            }
            return "Network request failed: \(error.localizedDescription)"
        case .invalidResponse: return "Received an invalid response from the miner."
        case .decodingError(let error, _):
            return "Failed to process data from the miner: \(error.localizedDescription)"
        case .apiError(let message): return "Miner API Error: \(message)"
        case .configurationMissing:
            return "Miner IP address is not configured. Please set it in the app."
        case .unknown: return "An unknown network error occurred."
        }
    }
}
