import Foundation

// Custom Error type for networking
enum NetworkError: Error, LocalizedError {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse
    case decodingError(Error)
    case apiError(message: String)
    case unknown
    case configurationMissing

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "The device IP address appears to be invalid."
        case .requestFailed(let error):
            // Check for specific network errors like timeout, no connection
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet:
                    return "Not connected to the internet. Please check your connection."
                case .cannotConnectToHost:
                    return
                        "Cannot connect to the BitAxe device. Ensure it's powered on and on the same network."
                case .timedOut:
                    return "The request timed out. The device might be busy or unreachable."
                default: return "Network request failed: \(urlError.localizedDescription)"
                }
            }
            return "Network request failed: \(error.localizedDescription)"
        case .invalidResponse: return "Received an invalid response from the device."
        case .decodingError(let error):
            return "Failed to process data from the device: \(error.localizedDescription)"
        case .apiError(let message): return "Device API Error: \(message)"
        case .configurationMissing:
            return "Device IP address is not configured. Please set it in the app."
        case .unknown: return "An unknown network error occurred."
        }
    }
}

actor NetworkService {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        // Configure decoder if needed (e.g., date strategies, key decoding strategy)
        // decoder.keyDecodingStrategy = .convertFromSnakeCase // If API uses snake_case
    }

    // Function to get the base URL, potentially from storage
    private func getBaseURL() -> URL? {
        let suiteName = "group.matthewramsden.traxe"

        guard let sharedDefaults = UserDefaults(suiteName: suiteName) else {
            return nil  // Return nil instead of throwing
        }

        guard let ipAddress = sharedDefaults.string(forKey: "bitaxeIPAddress"),
            !ipAddress.isEmpty
        else {
            return nil  // Return nil instead of throwing
        }

        // Clean up the IP address (remove any http:// or trailing slashes)
        let cleanIP = ipAddress.replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "/", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // This regex validates IPv4 addresses:
        // ^                     - Start of string
        // (                     - Start group for each octet
        //   25[0-5]            - Match numbers 250-255
        //   |2[0-4][0-9]       - Match numbers 200-249
        //   |[01]?[0-9][0-9]?  - Match numbers 0-199
        // ){3}                  - Repeat the octet group 3 times (first 3 numbers)
        // Same pattern for final octet, followed by end of string
        // Valid range: 0.0.0.0 to 255.255.255.255
        // Validate IP format
        let ipRegex =
            #"^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"#
        guard cleanIP.range(of: ipRegex, options: .regularExpression) != nil else {
            return nil  // Return nil for invalid format
        }

        // Construct URL
        guard let url = URL(string: "http://\(cleanIP)") else {
            return nil  // Return nil if URL construction fails
        }

        return url
    }

    // Generic GET request function
    func performGET<T: Codable>(endpoint: String) async throws -> T {
        guard let baseURL = getBaseURL() else {
            throw NetworkError.configurationMissing
        }
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0  // Increased timeout to 5 seconds

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
                    throw NetworkError.decodingError(error)
                }
            case 404:
                throw NetworkError.apiError(message: "Device not found at the specified IP address")
            case 500:
                throw NetworkError.apiError(message: "Device server error")
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
                case .notConnectedToInternet:
                    throw NetworkError.requestFailed(error)
                case .cannotConnectToHost:
                    throw NetworkError.requestFailed(error)
                case .timedOut:
                    throw NetworkError.requestFailed(error)
                default:
                    throw NetworkError.requestFailed(error)
                }
            }
            throw NetworkError.unknown
        }
    }

    // Specific endpoint functions
    func fetchSystemInfo() async throws -> SystemInfoDTO {
        try await performGET(endpoint: "/api/system/info")
    }

    func fetchSwarmInfo() async throws -> /* SwarmInfoDTO */ Codable {
        // Define SwarmInfoDTO similarly to SystemInfoDTO based on API response
        // For now, just returning a placeholder
        struct PlaceholderSwarmDTO: Codable { var message: String = "Swarm info placeholder" }
        return try await performGET(endpoint: "/api/swarm/info") as PlaceholderSwarmDTO
    }

    // Generic POST request function
    func performPOST(endpoint: String) async throws {
        guard let baseURL = getBaseURL() else {
            throw NetworkError.configurationMissing
        }
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30.0  // Longer timeout for firmware updates

        do {
            let (_, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200, 202:
                return  // Success
            case 404:
                throw NetworkError.apiError(message: "Endpoint not found")
            case 500:
                throw NetworkError.apiError(message: "Device server error")
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

    // Firmware update endpoints
    func updateFirmware() async throws {
        try await performPOST(endpoint: "/api/system/OTA")
    }

    func restartDevice() async throws {
        try await performPOST(endpoint: "/api/system/restart")
    }

    // Generic PATCH request function
    private func performPATCH<T: Encodable>(endpoint: String, body: T) async throws {
        guard let baseURL = getBaseURL() else {
            throw NetworkError.configurationMissing
        }
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5.0

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        do {
            let (_, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200, 202:
                return  // Success
            case 404:
                throw NetworkError.apiError(message: "Endpoint not found")
            case 500:
                throw NetworkError.apiError(message: "Device server error")
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

    // System settings update
    func updateSystemSettings(fanspeed: Int? = nil, autofanspeed: Int? = nil) async throws {
        struct SystemSettingsUpdate: Encodable {
            let fanspeed: Int?
            let autofanspeed: Int?
        }

        let update = SystemSettingsUpdate(fanspeed: fanspeed, autofanspeed: autofanspeed)
        try await performPATCH(endpoint: "/api/system", body: update)
    }
}
