import Foundation
import Observation
import RevenueCat

@MainActor
@Observable
final class SubscriptionStatusViewModel {
    private(set) var plan: SubscriptionSnapshot.Plan = .free
    private(set) var hasCurrentResponse = false
    private(set) var isRefreshing = false
    private(set) var refreshFailed = false
    private var refreshID: UUID?
    private var latestServerRequestDate: Date?
    private var observedOfflineSnapshots: Set<SubscriptionSnapshot> = []
    private var latestCurrentRequestDate: Date?
    private let cachedSnapshot: () -> SubscriptionSnapshot?
    private let fetchCurrent: () async throws -> SubscriptionSnapshot
    private let updates: () -> AsyncStream<SubscriptionSnapshot>

    init(
        cachedSnapshot: @escaping () -> SubscriptionSnapshot? = {
            Purchases.shared.cachedCustomerInfo.map(SubscriptionSnapshot.init)
        },
        fetchCurrent: @escaping () async throws -> SubscriptionSnapshot = {
            SubscriptionSnapshot(
                try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent)
            )
        },
        updates: @escaping () -> AsyncStream<SubscriptionSnapshot> = {
            AsyncStream { continuation in
                let task = Task {
                    for await info in Purchases.shared.customerInfoStream {
                        guard !Task.isCancelled else { break }
                        continuation.yield(SubscriptionSnapshot(info))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    ) {
        self.cachedSnapshot = cachedSnapshot
        self.fetchCurrent = fetchCurrent
        self.updates = updates
    }

    var accessPolicy: SubscriptionAccessPolicy {
        SubscriptionAccessPolicy(
            proIsActive: plan == .pro,
            miners5IsActive: plan == .miners5,
            hasLoadedSubscription: hasCurrentResponse
        )
    }

    var addDeviceLimit: Int {
        plan.deviceLimit
    }

    enum AddMinerDestination: Equatable {
        case addMiner
        case verifyPlan
        case viewPlans
    }

    func addMinerDestination(savedDeviceCount: Int) -> AddMinerDestination {
        if savedDeviceCount < addDeviceLimit { return .addMiner }
        return hasCurrentResponse ? .viewPlans : .verifyPlan
    }

    func refreshAfterRestore() async {
        // Restore may have populated an active cached entitlement even if a follow-up
        // server request fails. Positive cached evidence preserves its add allowance.
        if let cached = cachedSnapshot() { receiveCached(cached) }
        await refresh()
    }

    func observe() async {
        if let cached = cachedSnapshot() {
            receiveCached(cached)
        }
        await refresh()
        guard !Task.isCancelled else { return }
        for await snapshot in updates() {
            guard !Task.isCancelled else { return }
            receiveCached(snapshot)
            // The stream can replay a cache entry. A newer server downgrade needs a current
            // request before it can restrict access; an upgrade can grant access now.
            if !snapshot.isComputedOffline,
                snapshot.plan.rawValue < plan.rawValue,
                latestCurrentRequestDate.map({ snapshot.requestDate > $0 }) ?? true
            {
                await refresh()
            }
        }
    }

    func refresh() async {
        let requestID = UUID()
        refreshID = requestID
        isRefreshing = true
        defer {
            if refreshID == requestID { isRefreshing = false }
        }
        do {
            let snapshot = try await fetchCurrent()
            try Task.checkCancellation()
            guard refreshID == requestID else { return }
            receiveCurrent(snapshot)
            refreshFailed = !hasCurrentResponse || snapshot.isComputedOffline
        } catch {
            guard !Task.isCancelled, refreshID == requestID else { return }
            refreshFailed = true
        }
    }

    func receiveCached(_ snapshot: SubscriptionSnapshot) {
        if snapshot.isComputedOffline {
            // Offline dates use the device clock, so they cannot order server responses
            // or other offline results after a clock correction. Remember each result
            // only to prevent a stream replay from restoring a superseded grant.
            guard observedOfflineSnapshots.insert(snapshot).inserted else { return }
        } else {
            guard latestCurrentRequestDate.map({ snapshot.requestDate > $0 }) ?? true else {
                return
            }
            guard latestServerRequestDate.map({ snapshot.requestDate >= $0 }) ?? true else {
                return
            }
            latestServerRequestDate = snapshot.requestDate
        }
        // Cached data can preserve or increase access, never reduce it.
        if snapshot.plan.rawValue > plan.rawValue {
            plan = snapshot.plan
        }
    }

    func receiveCurrent(_ snapshot: SubscriptionSnapshot) {
        guard !snapshot.isComputedOffline else {
            receiveCached(snapshot)
            return
        }
        guard latestServerRequestDate.map({ snapshot.requestDate >= $0 }) ?? true else { return }
        latestServerRequestDate = snapshot.requestDate
        latestCurrentRequestDate = snapshot.requestDate
        plan = snapshot.plan
        hasCurrentResponse = true
    }
}
