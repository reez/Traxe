import Foundation
import Observation

/// Owns the AI summary shown on one miner's detail screen.
///
/// Every appearance and navigation lifecycle event funnels through
/// `loadSummary(for:historicalData:)`, which is single-flight per miner: a request that is
/// already running for the selected address is joined instead of started again, so repeated
/// events can only ever publish one result. Selecting a different miner cancels the previous
/// request and drops whatever it would have published, so a summary generated for a miner
/// that is no longer on screen can never replace the current one.
@Observable
@MainActor
final class DeviceAISummaryController {

    /// Generation is injected so the screen's lifecycle can run in tests and previews
    /// without Foundation Models or networking.
    struct Dependencies {
        var startDelay: Duration
        var generateSummary: (String, [HistoricalDataPoint]) async throws -> AISummary
    }

    private enum GenerationError: Error {
        case unsupportedSystemVersion
    }

    private(set) var summary: AISummary?
    private(set) var isGenerating = false

    private let dependencies: Dependencies
    private var request: Task<Void, Never>?
    private var requestedDeviceIP: String?
    /// Identifies the only request whose result may be published. Superseding or canceling a
    /// request advances it, so work that finishes anyway is rejected on its own merits rather
    /// than relying on it having observed cancellation.
    private var currentRequestID = 0

    init(dependencies: Dependencies? = nil) {
        self.dependencies = dependencies ?? (ProcessInfo.isPreview ? .preview : .live)
    }

    /// Generates the summary for `deviceIP` unless one is already published or already being
    /// generated for it. Safe to call from every lifecycle event that can fire for the screen.
    func loadSummary(for deviceIP: String, historicalData: [HistoricalDataPoint]) async {
        if requestedDeviceIP != deviceIP {
            cancelPendingWork()
            requestedDeviceIP = deviceIP
            summary = nil
        }

        guard summary == nil else { return }

        let request = self.request ?? startRequest(for: deviceIP, historicalData: historicalData)
        self.request = request
        await request.value
    }

    /// Drops in-flight work so a result that arrives after the miner changed is ignored,
    /// including one that completes despite being canceled.
    func cancelPendingWork() {
        currentRequestID += 1
        request?.cancel()
        request = nil
        isGenerating = false
    }

    private func startRequest(
        for deviceIP: String,
        historicalData: [HistoricalDataPoint]
    ) -> Task<Void, Never> {
        currentRequestID += 1
        let requestID = currentRequestID
        isGenerating = true

        return Task { [dependencies] in
            do {
                // Keeps the generating state on screen long enough to read while the
                // dashboard finishes loading the history the summary is built from.
                try await Task.sleep(for: dependencies.startDelay)
            } catch {
                return
            }

            let generated = try? await dependencies.generateSummary(deviceIP, historicalData)
            self.finishRequest(requestID, for: deviceIP, with: generated)
        }
    }

    private func finishRequest(_ requestID: Int, for deviceIP: String, with generated: AISummary?) {
        // Network or model work can finish even after its task was canceled, so a result is
        // only published while it is still the current request for the selected miner.
        guard requestID == currentRequestID, requestedDeviceIP == deviceIP else { return }

        request = nil
        isGenerating = false

        guard let generated else { return }
        summary = generated
    }
}

extension DeviceAISummaryController.Dependencies {

    static var live: Self {
        Self(startDelay: .milliseconds(500)) { deviceIP, historicalData in
            guard #available(iOS 18.0, macOS 15.0, *) else {
                throw DeviceAISummaryController.GenerationError.unsupportedSystemVersion
            }

            let service = AIAnalysisService()
            return try await service.generateDeviceSummary(
                forDevice: deviceIP,
                withHistoricalData: historicalData
            )
        }
    }

    static var preview: Self {
        Self(startDelay: .milliseconds(500)) { _, _ in
            let seeded = UserDefaults.standard.string(forKey: "preview_device_summary")
            return AISummary(
                content: seeded
                    ?? "Hashrate steady around 2.5 TH/s; temps mid‑60s °C; power ~620W. This miner's solo odds to hit a block are 1 in 5.7M today (15.7K yr expected)."
            )
        }
    }
}
