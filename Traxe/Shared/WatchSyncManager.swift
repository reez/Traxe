import Foundation

#if os(iOS)
    import WatchConnectivity

    final class WatchSyncManager: NSObject, WCSessionDelegate {
        static let shared = WatchSyncManager()

        private let appGroupID = "group.matthewramsden.traxe"
        private let deviceCacheKey = "cachedDeviceMetricsV2"
        private let legacyDataKey = "lastKnownWidgetData"

        private var pendingPayload: [String: Any]?
        private var lastPayload: [String: Any] = [:]

        private override init() {
            super.init()
            loadExistingPayloadFromDefaults()
            activateSession()
        }

        private func activateSession() {
            guard WCSession.isSupported() else { return }
            let session = WCSession.default
            if session.delegate == nil || !(session.delegate === self) {
                session.delegate = self
            }
            if session.activationState != .activated {
                session.activate()
            } else {
                attemptFlushPendingPayload()
            }
        }

        func updateCacheMetrics(_ metrics: [String: CachedDeviceMetrics]) {
            guard WCSession.isSupported() else { return }
            guard let payload = buildPayload(from: metrics) else { return }
            lastPayload = payload
            pendingPayload = payload
            attemptFlushPendingPayload()
        }

        // MARK: - WCSessionDelegate

        func session(
            _ session: WCSession,
            activationDidCompleteWith activationState: WCSessionActivationState,
            error: Error?
        ) {
            if error != nil {
                return
            }
            attemptFlushPendingPayload()
        }

        func sessionDidBecomeInactive(_ session: WCSession) {}

        func sessionDidDeactivate(_ session: WCSession) {
            session.activate()
        }

        func session(
            _ session: WCSession,
            didReceiveMessage message: [String: Any],
            replyHandler: @escaping ([String: Any]) -> Void
        ) {
            guard let request = message["request"] as? String, request == "hashrate" else { return }
            if lastPayload.isEmpty {
                loadExistingPayloadFromDefaults()
            }
            replyHandler(lastPayload)
        }

        func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
            lastPayload = userInfo
        }

        func sessionReachabilityDidChange(_ session: WCSession) {
            if !lastPayload.isEmpty {
                pendingPayload = lastPayload
            }
            attemptFlushPendingPayload()
        }

        // MARK: - Helpers

        private func attemptFlushPendingPayload() {
            guard WCSession.isSupported() else { return }
            guard let payload = pendingPayload else { return }

            let session = WCSession.default
            if session.activationState != .activated {
                session.activate()
                return
            }

            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
            }
            session.transferUserInfo(payload)
            pendingPayload = nil
        }

        private func buildPayload(from metrics: [String: CachedDeviceMetrics]) -> [String: Any]? {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(metrics) else { return nil }

            let deviceCount =
                (UserDefaults(suiteName: appGroupID)?
                .array(forKey: "savedDeviceIPs") as? [String])?.count ?? metrics.count
            let snapshot = FleetMetricSnapshot.make(
                readings: metrics.map { $0.value.reading(id: $0.key) },
                totalDevices: deviceCount
            )
            var payload: [String: Any] = ["cacheData": data, "deviceCount": deviceCount]
            if let totalHashrate = snapshot.totalHashrate {
                payload["totalHashrate"] = totalHashrate
            }
            if let measuredAt = snapshot.measuredAt { payload["lastUpdated"] = measuredAt }
            return payload
        }

        private func loadExistingPayloadFromDefaults() {
            guard
                let defaults = UserDefaults(suiteName: appGroupID),
                let data = defaults.data(forKey: deviceCacheKey)
            else {
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let metrics = try? decoder.decode([String: CachedDeviceMetrics].self, from: data),
                var payload = buildPayload(from: metrics)
            else {
                return
            }

            if let legacy = defaults.dictionary(forKey: legacyDataKey),
                let hashrate = legacy["hashrate"] as? String
            {
                payload["legacyHashrateString"] = hashrate
            }

            lastPayload = payload
        }
    }
#endif
