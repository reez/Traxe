import Foundation
import WatchKit
import WidgetKit

final class WatchBackgroundRefreshManager: NSObject, WKApplicationDelegate {
    private let refreshInterval: TimeInterval = 10 * 60

    override init() {
        super.init()
        _ = WatchSessionManager.shared
    }

    func applicationDidFinishLaunching() {
        scheduleNextRefresh(immediate: true)
        Task { await triggerSync(context: "launch") }
    }

    func applicationDidBecomeActive() {
        scheduleNextRefresh(immediate: false)
        Task { await triggerSync(context: "becomeActive") }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let refreshTask as WKApplicationRefreshBackgroundTask:
                handleRefreshTask(refreshTask)
            case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
                handleConnectivityTask(connectivityTask)
            case let urlTask as WKURLSessionRefreshBackgroundTask:
                urlTask.setTaskCompletedWithSnapshot(false)
            case let snapshot as WKSnapshotRefreshBackgroundTask:
                snapshot.setTaskCompleted(
                    restoredDefaultState: true,
                    estimatedSnapshotExpiration: Date.distantFuture,
                    userInfo: nil
                )
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    private func handleRefreshTask(_ task: WKApplicationRefreshBackgroundTask) {
        Task {
            await triggerSync(context: "refreshTask")
            task.setTaskCompletedWithSnapshot(false)
        }
    }

    private func handleConnectivityTask(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        Task {
            await triggerSync(context: "connectivityTask")
            task.setTaskCompletedWithSnapshot(false)
        }
    }

    @MainActor
    private func triggerSync(context: String) async {
        WatchSessionManager.shared.requestHashrateUpdate(reason: context)
        WatchSessionManager.shared.reapplyCachedDataIfAvailable()
        WidgetCenter.shared.reloadTimelines(ofKind: "TraxeWatchWidget")
        scheduleNextRefresh(immediate: false)
    }

    private func scheduleNextRefresh(immediate: Bool) {
        let date = Date().addingTimeInterval(immediate ? 60 : refreshInterval)
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: date, userInfo: nil) {
            _ in
        }
    }
}
