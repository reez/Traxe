import Foundation
import WatchConnectivity
import WidgetKit

final class WatchSessionManager: NSObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    private let appGroupID = "group.matthewramsden.traxe"
    private let deviceCacheKey = "cachedDeviceMetricsV2"
    private let legacyDataKey = "lastKnownWidgetData"

    private override init() {
        super.init()
        activateSession()
    }

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func requestHashrateUpdate(reason: String = "unspecified") {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default

        if session.activationState != .activated {
            session.activate()
            return
        }

        guard session.isReachable else { return }

        session.sendMessage(
            ["request": "hashrate"],
            replyHandler: { [weak self] reply in
                self?.apply(payload: reply)
            },
            errorHandler: nil
        )
    }

    func reapplyCachedDataIfAvailable() {
        guard let defaults = UserDefaults(suiteName: appGroupID),
            let data = defaults.data(forKey: deviceCacheKey)
        else {
            return
        }
        defaults.set(data, forKey: deviceCacheKey)
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        apply(payload: message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        apply(payload: userInfo)
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        apply(payload: applicationContext)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable {
            requestHashrateUpdate(reason: "reachabilityChanged")
        }
    }

    // MARK: - Helpers

    private func apply(payload: [String: Any]) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }

        if let data = payload["cacheData"] as? Data {
            defaults.set(data, forKey: deviceCacheKey)
        }

        if let totalNumber = payload["totalHashrate"] as? NSNumber {
            let total = totalNumber.doubleValue
            storeLegacyHashrate(
                value: total.formattedHashRateWithUnit().value,
                unit: total.formattedHashRateWithUnit().unit,
                date: payload["lastUpdated"] as? Date,
                deviceCount: (payload["deviceCount"] as? NSNumber)?.intValue
            )
        } else if let total = payload["totalHashrate"] as? Double {
            storeLegacyHashrate(
                value: total.formattedHashRateWithUnit().value,
                unit: total.formattedHashRateWithUnit().unit,
                date: payload["lastUpdated"] as? Date,
                deviceCount: (payload["deviceCount"] as? NSNumber)?.intValue
            )
        } else if let legacyString = payload["legacyHashrateString"] as? String {
            storeLegacyHashrate(
                value: legacyString,
                unit: "",
                date: payload["lastUpdated"] as? Date,
                deviceCount: (payload["deviceCount"] as? NSNumber)?.intValue
            )
        }

        Task { @MainActor in
            NotificationCenter.default.post(name: .watchHashrateDidUpdate, object: nil)
            WidgetCenter.shared.reloadTimelines(ofKind: "TraxeWatchWidget")
        }
    }

    private func storeLegacyHashrate(value: String, unit: String, date: Date?, deviceCount: Int?) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        let payload: [String: Any] = [
            "hashrate": value,
            "unit": unit,
            "cachedDate": date ?? Date(),
            "totalDevices": deviceCount ?? 0,
        ]
        defaults.set(payload, forKey: legacyDataKey)
    }
}

extension Notification.Name {
    static let watchHashrateDidUpdate = Notification.Name("watchHashrateDidUpdate")
}
