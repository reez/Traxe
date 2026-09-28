import Foundation
import XCTest

@testable import Traxe

@MainActor
final class PaywallOutcomeViewModelTests: XCTestCase {
    func testPurchaseWithoutEntitlementHoldsSDKDismissalAndShowsPurchaseRecovery() {
        let viewModel = PaywallOutcomeViewModel()
        viewModel.beginAction()

        XCTAssertFalse(viewModel.completePurchase(hasActivePlan: false))

        XCTAssertTrue(viewModel.purchaseNeedsRecovery)
        XCTAssertFalse(viewModel.isActionInProgress)
        XCTAssertFalse(viewModel.showingRestoreMessage)
        XCTAssertFalse(viewModel.permitsSDKDismissal)
        XCTAssertTrue(viewModel.recoveryMessage.contains("Your purchase completed"))
        XCTAssertTrue(viewModel.recoveryMessage.contains("don’t need to buy it again"))
    }

    func testRestoreWithoutEntitlementShowsRestoreMessageUntilAcknowledged() {
        let viewModel = PaywallOutcomeViewModel()
        viewModel.beginAction()

        XCTAssertFalse(viewModel.completeRestore(hasActivePlan: false))

        XCTAssertFalse(viewModel.purchaseNeedsRecovery)
        XCTAssertTrue(viewModel.showingRestoreMessage)
        XCTAssertFalse(viewModel.permitsSDKDismissal)
        viewModel.showingRestoreMessage = false
        XCTAssertTrue(viewModel.permitsSDKDismissal)
    }

    func testSuccessfulPurchaseAndRestoreAllowDismissal() {
        let viewModel = PaywallOutcomeViewModel()
        viewModel.beginAction()
        XCTAssertFalse(viewModel.permitsSDKDismissal)
        XCTAssertTrue(viewModel.completePurchase(hasActivePlan: true))
        XCTAssertTrue(viewModel.permitsSDKDismissal)

        viewModel.beginAction()
        XCTAssertTrue(viewModel.completeRestore(hasActivePlan: true))
        XCTAssertTrue(viewModel.permitsSDKDismissal)
    }

    func testFailedPurchaseVerificationCanBeRetriedWithoutRepurchasing() async {
        var attempts = 0
        let viewModel = PaywallOutcomeViewModel(syncPurchase: {
            attempts += 1
            if attempts == 1 { throw URLError(.notConnectedToInternet) }
            return true
        })
        _ = viewModel.completePurchase(hasActivePlan: false)

        let firstAttempt = await viewModel.retryActivation()
        XCTAssertFalse(firstAttempt)
        XCTAssertTrue(viewModel.purchaseNeedsRecovery)
        XCTAssertFalse(viewModel.isActionInProgress)
        XCTAssertFalse(viewModel.permitsSDKDismissal)

        let secondAttempt = await viewModel.retryActivation()
        XCTAssertTrue(secondAttempt)
        XCTAssertEqual(attempts, 2)
        XCTAssertFalse(viewModel.purchaseNeedsRecovery)
        XCTAssertTrue(viewModel.permitsSDKDismissal)
    }

    func testVerificationWithoutPlanKeepsRecoveryVisible() async {
        let viewModel = PaywallOutcomeViewModel(syncPurchase: { false })
        _ = viewModel.completePurchase(hasActivePlan: false)

        let restored = await viewModel.retryActivation()

        XCTAssertFalse(restored)
        XCTAssertTrue(viewModel.purchaseNeedsRecovery)
        XCTAssertFalse(viewModel.permitsSDKDismissal)
        XCTAssertTrue(viewModel.recoveryMessage.contains("contact support"))
    }

    func testVerificationIgnoresDuplicateRequestsWhileInFlight() async {
        var continuation: CheckedContinuation<Bool, Never>?
        var attempts = 0
        let started = expectation(description: "Verification reached the suspended operation")
        let viewModel = PaywallOutcomeViewModel(syncPurchase: {
            attempts += 1
            return await withCheckedContinuation {
                continuation = $0
                started.fulfill()
            }
        })
        _ = viewModel.completePurchase(hasActivePlan: false)
        let firstAttempt = Task { await viewModel.retryActivation() }
        await fulfillment(of: [started], timeout: 2)
        guard let pendingVerification = continuation else {
            firstAttempt.cancel()
            return
        }

        let duplicateAttempt = await viewModel.retryActivation()

        XCTAssertFalse(duplicateAttempt)
        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(viewModel.isActionInProgress)
        pendingVerification.resume(returning: true)
        let completed = await firstAttempt.value
        XCTAssertTrue(completed)
        XCTAssertFalse(viewModel.isActionInProgress)
    }
}
