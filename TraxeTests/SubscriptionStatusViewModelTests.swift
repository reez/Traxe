import Foundation
import XCTest

@testable import Traxe

@MainActor
final class SubscriptionStatusViewModelTests: XCTestCase {
    func testConstructionDoesNotReadLiveCacheOrStartRequests() {
        var cacheReads = 0
        var requests = 0
        let viewModel = SubscriptionStatusViewModel(
            cachedSnapshot: {
                cacheReads += 1
                return SubscriptionSnapshot(plan: .free, requestDate: .distantPast)
            },
            fetchCurrent: {
                requests += 1
                return SubscriptionSnapshot(plan: .free, requestDate: Date())
            }
        )

        XCTAssertEqual(cacheReads, 0)
        XCTAssertEqual(requests, 0)
        XCTAssertFalse(viewModel.accessPolicy.shouldShowLocks)
        XCTAssertEqual(viewModel.addDeviceLimit, 1)
    }

    func testCachedFreePlanDoesNotLockExistingMinersWhenOffline() async {
        let viewModel = SubscriptionStatusViewModel(
            cachedSnapshot: {
                SubscriptionSnapshot(plan: .free, requestDate: Date(timeIntervalSince1970: 100))
            },
            fetchCurrent: { throw URLError(.notConnectedToInternet) },
            updates: { AsyncStream { $0.finish() } }
        )

        await viewModel.observe()

        XCTAssertTrue(viewModel.refreshFailed)
        XCTAssertFalse(viewModel.hasCurrentResponse)
        XCTAssertTrue(viewModel.accessPolicy.isDeviceAccessible(at: 7))
        XCTAssertEqual(viewModel.addDeviceLimit, 1)
    }

    func testCachedPaidPlanPreservesExistingAccessAndItsAddAllowance() async {
        let viewModel = SubscriptionStatusViewModel(
            cachedSnapshot: {
                SubscriptionSnapshot(plan: .miners5, requestDate: .distantPast)
            },
            fetchCurrent: { throw URLError(.notConnectedToInternet) },
            updates: { AsyncStream { $0.finish() } }
        )

        await viewModel.observe()

        XCTAssertEqual(viewModel.plan, .miners5)
        XCTAssertEqual(viewModel.addDeviceLimit, 5)
        XCTAssertTrue(viewModel.accessPolicy.isDeviceAccessible(at: 7))
        XCTAssertFalse(viewModel.accessPolicy.shouldShowLocks)
    }

    func testCurrentResponsesApplyFreeAndPaidTierLimits() {
        let viewModel = SubscriptionStatusViewModel()
        viewModel.receiveCurrent(.init(plan: .free, requestDate: Date(timeIntervalSince1970: 100)))
        XCTAssertEqual(viewModel.accessPolicy.deviceLimit, 1)
        XCTAssertEqual(viewModel.addDeviceLimit, 1)

        viewModel.receiveCurrent(
            .init(plan: .miners5, requestDate: Date(timeIntervalSince1970: 200))
        )
        XCTAssertEqual(viewModel.accessPolicy.deviceLimit, 5)
        XCTAssertEqual(viewModel.addDeviceLimit, 5)

        viewModel.receiveCurrent(.init(plan: .pro, requestDate: Date(timeIntervalSince1970: 300)))
        XCTAssertEqual(viewModel.accessPolicy.deviceLimit, Int.max)
        XCTAssertEqual(viewModel.addDeviceLimit, Int.max)
    }

    func testCachedDowngradeCannotReplaceVerifiedPlanAndCurrentResponseCan() {
        let viewModel = SubscriptionStatusViewModel()
        viewModel.receiveCurrent(.init(plan: .pro, requestDate: Date(timeIntervalSince1970: 100)))
        viewModel.receiveCached(.init(plan: .free, requestDate: Date(timeIntervalSince1970: 200)))
        XCTAssertEqual(viewModel.accessPolicy.deviceLimit, Int.max)

        viewModel.receiveCurrent(.init(plan: .free, requestDate: Date(timeIntervalSince1970: 200)))
        XCTAssertEqual(viewModel.accessPolicy.deviceLimit, 1)
        XCTAssertTrue(viewModel.hasCurrentResponse)
    }

    func testOlderResponsesAndReplayedCacheCannotOverrideNewerState() {
        let viewModel = SubscriptionStatusViewModel()
        viewModel.receiveCached(.init(plan: .pro, requestDate: Date(timeIntervalSince1970: 200)))
        viewModel.receiveCurrent(.init(plan: .free, requestDate: Date(timeIntervalSince1970: 100)))
        XCTAssertEqual(viewModel.plan, .pro)
        XCTAssertFalse(viewModel.hasCurrentResponse)

        viewModel.receiveCurrent(.init(plan: .free, requestDate: Date(timeIntervalSince1970: 300)))
        viewModel.receiveCached(.init(plan: .pro, requestDate: Date(timeIntervalSince1970: 200)))
        viewModel.receiveCached(.init(plan: .pro, requestDate: Date(timeIntervalSince1970: 300)))
        XCTAssertEqual(viewModel.plan, .free)
        XCTAssertEqual(viewModel.accessPolicy.deviceLimit, 1)
    }

    func testOfflineComputedResponseCannotAuthorizeDowngrade() async {
        let viewModel = SubscriptionStatusViewModel(
            fetchCurrent: {
                SubscriptionSnapshot(plan: .free, requestDate: Date(), isComputedOffline: true)
            }
        )

        await viewModel.refresh()

        XCTAssertTrue(viewModel.refreshFailed)
        XCTAssertFalse(viewModel.hasCurrentResponse)
        XCTAssertFalse(viewModel.accessPolicy.shouldShowLocks)
    }

    func testFutureDatedOfflineResponseAllowsServerRecoveryAndCannotReplayItsGrant() async {
        let offline = SubscriptionSnapshot(
            plan: .pro,
            requestDate: Date(timeIntervalSince1970: 1_000_000),
            isComputedOffline: true
        )
        var requests = 0
        let viewModel = SubscriptionStatusViewModel(fetchCurrent: {
            requests += 1
            return requests == 1
                ? offline
                : SubscriptionSnapshot(plan: .free, requestDate: Date(timeIntervalSince1970: 100))
        })

        await viewModel.refresh()
        XCTAssertEqual(viewModel.plan, .pro)
        XCTAssertTrue(viewModel.refreshFailed)
        XCTAssertFalse(viewModel.hasCurrentResponse)

        await viewModel.refresh()
        XCTAssertEqual(viewModel.plan, .free)
        XCTAssertFalse(viewModel.refreshFailed)
        XCTAssertTrue(viewModel.hasCurrentResponse)

        viewModel.receiveCached(offline)
        XCTAssertEqual(viewModel.plan, .free)
        XCTAssertEqual(viewModel.addDeviceLimit, 1)
    }

    func testCorrectingOfflineClockBackwardStillAllowsNewGrantsAndServerUpdates() {
        let futureOffline = SubscriptionSnapshot(
            plan: .pro,
            requestDate: Date(timeIntervalSince1970: 1_000_000),
            isComputedOffline: true
        )
        let correctedOffline = SubscriptionSnapshot(
            plan: .miners5,
            requestDate: Date(timeIntervalSince1970: 10),
            isComputedOffline: true
        )
        let viewModel = SubscriptionStatusViewModel()
        viewModel.receiveCurrent(.init(plan: .free, requestDate: Date(timeIntervalSince1970: 100)))
        viewModel.receiveCached(futureOffline)
        XCTAssertEqual(viewModel.plan, .pro)

        viewModel.receiveCurrent(.init(plan: .free, requestDate: Date(timeIntervalSince1970: 200)))
        XCTAssertEqual(viewModel.plan, .free)

        viewModel.receiveCurrent(correctedOffline)
        XCTAssertEqual(viewModel.plan, .miners5)
        viewModel.receiveCached(futureOffline)
        XCTAssertEqual(viewModel.plan, .miners5)

        viewModel.receiveCurrent(.init(plan: .free, requestDate: Date(timeIntervalSince1970: 300)))
        viewModel.receiveCached(correctedOffline)
        XCTAssertEqual(viewModel.plan, .free)
    }

    func testOfflineClockDoesNotReplaceOrderingOfCachedAndCurrentServerResponses() {
        let viewModel = SubscriptionStatusViewModel()
        viewModel.receiveCached(
            .init(
                plan: .free,
                requestDate: Date(timeIntervalSince1970: 1_000_000),
                isComputedOffline: true
            )
        )
        viewModel.receiveCached(.init(plan: .miners5, requestDate: Date(timeIntervalSince1970: 200)))
        XCTAssertEqual(viewModel.plan, .miners5)

        viewModel.receiveCurrent(.init(plan: .free, requestDate: Date(timeIntervalSince1970: 100)))
        XCTAssertEqual(viewModel.plan, .miners5)
        XCTAssertFalse(viewModel.hasCurrentResponse)

        viewModel.receiveCurrent(.init(plan: .free, requestDate: Date(timeIntervalSince1970: 300)))
        viewModel.receiveCached(.init(plan: .pro, requestDate: Date(timeIntervalSince1970: 200)))
        XCTAssertEqual(viewModel.plan, .free)
        XCTAssertTrue(viewModel.hasCurrentResponse)
    }

    func testOfflineStreamDowngradesDoNotStartAutomaticRefreshes() async {
        var requests = 0
        let viewModel = SubscriptionStatusViewModel(
            cachedSnapshot: {
                .init(plan: .miners5, requestDate: Date(timeIntervalSince1970: 100))
            },
            fetchCurrent: {
                requests += 1
                return .init(
                    plan: .free,
                    requestDate: Date(timeIntervalSince1970: 200),
                    isComputedOffline: true
                )
            },
            updates: {
                AsyncStream {
                    for timestamp in [200.0, 201.0, 202.0] {
                        $0.yield(
                            .init(
                                plan: .free,
                                requestDate: Date(timeIntervalSince1970: timestamp),
                                isComputedOffline: true
                            )
                        )
                    }
                    $0.finish()
                }
            }
        )

        await viewModel.observe()

        XCTAssertEqual(requests, 1)
        XCTAssertEqual(viewModel.plan, .miners5)
        XCTAssertEqual(viewModel.addDeviceLimit, 5)
        XCTAssertTrue(viewModel.accessPolicy.isDeviceAccessible(at: 4))
        XCTAssertFalse(viewModel.hasCurrentResponse)
        XCTAssertTrue(viewModel.refreshFailed)
        XCTAssertFalse(viewModel.isRefreshing)
    }

    func testNewerStreamDowngradeRequiresCurrentFetch() async {
        var requests = 0
        let viewModel = SubscriptionStatusViewModel(
            cachedSnapshot: { nil },
            fetchCurrent: {
                requests += 1
                return SubscriptionSnapshot(
                    plan: requests == 1 ? .pro : .free,
                    requestDate: Date(timeIntervalSince1970: requests == 1 ? 100 : 200)
                )
            },
            updates: {
                AsyncStream {
                    $0.yield(.init(plan: .free, requestDate: Date(timeIntervalSince1970: 200)))
                    $0.finish()
                }
            }
        )

        await viewModel.observe()

        XCTAssertEqual(requests, 2)
        XCTAssertEqual(viewModel.accessPolicy.deviceLimit, 1)
    }

    func testFailedCurrentRefreshCanRecoverWithoutRestart() async {
        var requests = 0
        let viewModel = SubscriptionStatusViewModel(fetchCurrent: {
            requests += 1
            if requests == 1 { throw URLError(.notConnectedToInternet) }
            return SubscriptionSnapshot(plan: .miners5, requestDate: Date())
        })

        await viewModel.refresh()
        XCTAssertTrue(viewModel.refreshFailed)
        XCTAssertFalse(viewModel.accessPolicy.shouldShowLocks)

        await viewModel.refresh()
        XCTAssertFalse(viewModel.refreshFailed)
        XCTAssertTrue(viewModel.hasCurrentResponse)
        XCTAssertEqual(viewModel.accessPolicy.deviceLimit, 5)
    }

    func testCancelledRefreshCannotReplaceNewerForegroundRequest() async {
        var suspendedRequest: CheckedContinuation<SubscriptionSnapshot, Never>?
        var requests = 0
        let viewModel = SubscriptionStatusViewModel(fetchCurrent: {
            requests += 1
            if requests == 1 {
                return await withCheckedContinuation { suspendedRequest = $0 }
            }
            return SubscriptionSnapshot(plan: .pro, requestDate: Date(timeIntervalSince1970: 200))
        })
        let oldRefresh = Task { await viewModel.refresh() }
        while suspendedRequest == nil { await Task.yield() }
        oldRefresh.cancel()

        await viewModel.refresh()
        suspendedRequest?.resume(
            returning: .init(plan: .free, requestDate: Date(timeIntervalSince1970: 300))
        )
        await oldRefresh.value

        XCTAssertEqual(requests, 2)
        XCTAssertEqual(viewModel.plan, .pro)
        XCTAssertTrue(viewModel.hasCurrentResponse)
        XCTAssertFalse(viewModel.isRefreshing)
    }
    func testUnverifiedPlanAtAddLimitRoutesToVerificationAndFreeSlotRemainsAvailable() async {
        let viewModel = SubscriptionStatusViewModel(
            cachedSnapshot: { nil },
            fetchCurrent: { throw URLError(.notConnectedToInternet) }
        )
        XCTAssertEqual(viewModel.addMinerDestination(savedDeviceCount: 0), .addMiner)
        XCTAssertEqual(viewModel.addMinerDestination(savedDeviceCount: 1), .verifyPlan)

        await viewModel.refresh()

        XCTAssertTrue(viewModel.refreshFailed)
        XCTAssertEqual(viewModel.addDeviceLimit, 1)
        XCTAssertEqual(viewModel.addMinerDestination(savedDeviceCount: 1), .verifyPlan)
        XCTAssertEqual(viewModel.addMinerDestination(savedDeviceCount: 4), .verifyPlan)
    }

    func testCachedPaidPlanAllowsAddingWithinKnownAllowanceWithoutOpeningPlans() async {
        let viewModel = SubscriptionStatusViewModel(
            cachedSnapshot: {
                SubscriptionSnapshot(plan: .miners5, requestDate: .distantPast)
            },
            fetchCurrent: { throw URLError(.notConnectedToInternet) },
            updates: { AsyncStream { $0.finish() } }
        )

        await viewModel.observe()

        XCTAssertEqual(viewModel.addMinerDestination(savedDeviceCount: 4), .addMiner)
        XCTAssertEqual(viewModel.addMinerDestination(savedDeviceCount: 5), .verifyPlan)
    }

    func testRetryRoutesToAddOrPlansOnlyAfterCurrentVerification() async {
        for plan in [SubscriptionSnapshot.Plan.free, .miners5] {
            let viewModel = SubscriptionStatusViewModel(
                cachedSnapshot: { nil },
                fetchCurrent: { SubscriptionSnapshot(plan: plan, requestDate: Date()) }
            )
            XCTAssertEqual(viewModel.addMinerDestination(savedDeviceCount: 1), .verifyPlan)

            await viewModel.refresh()

            XCTAssertEqual(
                viewModel.addMinerDestination(savedDeviceCount: 1),
                plan == .free ? .viewPlans : .addMiner
            )
            XCTAssertEqual(viewModel.addMinerDestination(savedDeviceCount: 5), .viewPlans)
        }
    }

    func testSuccessfulRestoreUsesCachedPaidAllowanceWhenFollowupFetchFails() async {
        let viewModel = SubscriptionStatusViewModel(
            cachedSnapshot: { SubscriptionSnapshot(plan: .miners5, requestDate: Date()) },
            fetchCurrent: { throw URLError(.notConnectedToInternet) }
        )
        XCTAssertEqual(viewModel.addMinerDestination(savedDeviceCount: 1), .verifyPlan)

        await viewModel.refreshAfterRestore()

        XCTAssertTrue(viewModel.refreshFailed)
        XCTAssertFalse(viewModel.hasCurrentResponse)
        XCTAssertEqual(viewModel.addDeviceLimit, 5)
        XCTAssertEqual(viewModel.addMinerDestination(savedDeviceCount: 1), .addMiner)
    }

}
