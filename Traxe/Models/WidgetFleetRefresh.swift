import Foundation

/// Collects one widget poll, then reconciles it against the shared state that
/// exists when the requests finish. Another app window may update that state
/// while the widget is waiting on an unreachable miner.
struct WidgetFleetRefresh<Metrics: Sendable> {
    struct State: Sendable {
        let ipAddresses: [String]
        let savedDevicesData: Data?
        let metricsByIP: [String: Metrics]
    }

    struct Response: Sendable {
        let hashrate: Double?
        let temperature: Double?
    }

    struct Result: Sendable {
        let state: State
        let responses: [String: Response]
        let canApplyResponses: Bool
    }

    @MainActor
    static func run(
        initialState: State,
        fetch: @escaping @Sendable (String) async throws -> Response,
        loadCurrentState: @MainActor () -> State
    ) async -> Result {
        let responses = await withTaskGroup(of: (String, Response?).self) { group in
            for ip in initialState.ipAddresses {
                group.addTask { (ip, try? await fetch(ip)) }
            }
            var responses: [String: Response] = [:]
            for await (ip, response) in group {
                responses[ip] = response
            }
            return responses
        }
        let currentState = loadCurrentState()
        // The saved payload contains stable miner IDs as well as addresses.
        // Conservatively discard this poll if identity or topology changed,
        // including a replacement at an unchanged IP, and use the current cache.
        let sameFleet = initialState.ipAddresses == currentState.ipAddresses
            && initialState.savedDevicesData == currentState.savedDevicesData
        return Result(
            state: currentState,
            responses: sameFleet ? responses : [:],
            canApplyResponses: sameFleet
        )
    }
}
