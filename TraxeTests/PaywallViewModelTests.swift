import Foundation
import XCTest

@testable import Traxe

@MainActor
final class PaywallViewModelTests: XCTestCase {
    func testFailedOfferingRequestExposesRecoverableError() async {
        let viewModel = PaywallViewModel(fetchOffering: {
            throw URLError(.notConnectedToInternet)
        })

        await viewModel.loadOffering()

        XCTAssertNil(viewModel.currentOffering)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testMissingOfferingExposesErrorInsteadOfKeepingSpinner() async {
        let viewModel = PaywallViewModel(fetchOffering: { nil })

        await viewModel.loadOffering()

        XCTAssertNil(viewModel.currentOffering)
        XCTAssertEqual(
            viewModel.errorMessage,
            "Plans aren’t available right now. Please try again."
        )
    }

    func testRetryMakesAnotherRequestAndClearsPreviousErrorWhileLoading() async {
        var requestCount = 0
        var pendingRequest: CheckedContinuation<Void, Never>?
        let viewModel = PaywallViewModel(fetchOffering: {
            requestCount += 1
            if requestCount == 1 {
                throw URLError(.notConnectedToInternet)
            }
            await withCheckedContinuation { pendingRequest = $0 }
            return nil
        })
        await viewModel.loadOffering()
        XCTAssertNotNil(viewModel.errorMessage)

        let retry = Task { await viewModel.loadOffering() }
        while pendingRequest == nil {
            await Task.yield()
        }
        XCTAssertEqual(requestCount, 2)
        XCTAssertNil(viewModel.errorMessage)
        pendingRequest?.resume()
        await retry.value
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testCancelledRequestDoesNotPublishAnErrorAfterDismissal() async {
        var pendingRequest: CheckedContinuation<Void, Never>?
        let viewModel = PaywallViewModel(fetchOffering: {
            await withCheckedContinuation { pendingRequest = $0 }
            throw URLError(.cancelled)
        })
        let task = Task { await viewModel.loadOffering() }
        while pendingRequest == nil {
            await Task.yield()
        }

        task.cancel()
        pendingRequest?.resume()
        await task.value

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.currentOffering)
    }
}
