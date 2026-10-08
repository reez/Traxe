import Foundation
import XCTest

@testable import Traxe

@MainActor
final class RestorePurchasesViewModelTests: XCTestCase {
    func testRestoreWithoutActivePlanReportsNoPurchaseFound() async {
        let viewModel = RestorePurchasesViewModel(restorePurchases: { false })

        let restored = await viewModel.restore()

        XCTAssertFalse(restored)
        XCTAssertFalse(viewModel.isRestoring)
        XCTAssertEqual(viewModel.message, "No active Traxe plan was found for this Apple Account.")
    }

    func testSuccessfulRestoreReportsRestoredPlan() async {
        let viewModel = RestorePurchasesViewModel(restorePurchases: { true })

        let restored = await viewModel.restore()

        XCTAssertTrue(restored)
        XCTAssertFalse(viewModel.isRestoring)
        XCTAssertEqual(viewModel.message, "Your Traxe plan has been restored.")
    }

    func testRestoreCanRetryAfterNetworkFailure() async {
        var attempts = 0
        let viewModel = RestorePurchasesViewModel(restorePurchases: {
            attempts += 1
            if attempts == 1 { throw URLError(.notConnectedToInternet) }
            return true
        })

        let firstResult = await viewModel.restore()
        XCTAssertFalse(firstResult)
        XCTAssertFalse(viewModel.isRestoring)
        XCTAssertEqual(
            viewModel.message,
            "Couldn’t restore purchases right now. Please try again shortly."
        )

        let retryResult = await viewModel.restore()
        XCTAssertTrue(retryResult)
        XCTAssertEqual(attempts, 2)
        XCTAssertFalse(viewModel.isRestoring)
    }
}
