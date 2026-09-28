import XCTest

@testable import Traxe

final class PlanVerificationPresentationTests: XCTestCase {
    func testExplicitViewPlansWaitsForDismissalAndIgnoresLateVerification() {
        var presentation = PlanVerificationPresentation()
        presentation.present()

        presentation.complete(.viewPlans)
        XCTAssertFalse(presentation.isPresented)
        presentation.complete(.verified)

        XCTAssertEqual(presentation.didDismiss(), .viewPlans)
        XCTAssertNil(presentation.didDismiss())
    }

    func testClosingVerificationDoesNotContinueOrAcceptLateCallbacks() {
        var presentation = PlanVerificationPresentation()
        presentation.present()
        presentation.isPresented = false

        presentation.complete(.verified)
        presentation.complete(.viewPlans)

        XCTAssertNil(presentation.didDismiss())
        XCTAssertFalse(presentation.isPresented)
    }

    func testSuccessfulVerificationContinuesOnceAndNewPresentationStartsClean() {
        var presentation = PlanVerificationPresentation()
        presentation.present()
        presentation.complete(.verified)

        XCTAssertFalse(presentation.isPresented)
        XCTAssertEqual(presentation.didDismiss(), .verified)
        XCTAssertNil(presentation.didDismiss())

        presentation.present()
        XCTAssertTrue(presentation.isPresented)
        presentation.isPresented = false
        XCTAssertNil(presentation.didDismiss())
    }

    func testViewPlansOpensOnlyPaywallAfterDismissalEvenWhenRetryGrantsAccess() {
        for destination in [
            SubscriptionStatusViewModel.AddMinerDestination.addMiner, .verifyPlan, .viewPlans,
        ] {
            var presentation = PlanVerificationPresentation()
            presentation.presentAddMiner(destination: .verifyPlan)
            presentation.complete(.viewPlans)
            XCTAssertFalse(presentation.showingPlans)
            XCTAssertFalse(presentation.showingAddMiner)

            presentation.routeAfterDismissal(destination: destination)

            XCTAssertTrue(presentation.showingPlans)
            XCTAssertFalse(presentation.showingAddMiner)
            XCTAssertFalse(presentation.isPresented)
        }
    }

    func testVerifiedDismissalRoutesToCurrentAllowanceAndCancellationOpensNothing() {
        for destination in [SubscriptionStatusViewModel.AddMinerDestination.addMiner, .viewPlans] {
            var presentation = PlanVerificationPresentation()
            presentation.present()
            presentation.complete(.verified)
            XCTAssertFalse(presentation.showingPlans)
            XCTAssertFalse(presentation.showingAddMiner)

            presentation.routeAfterDismissal(destination: destination)
            XCTAssertEqual(presentation.showingAddMiner, destination == .addMiner)
            XCTAssertEqual(presentation.showingPlans, destination == .viewPlans)
            XCTAssertFalse(presentation.isPresented)

            presentation.showingPlans = false
            presentation.showingAddMiner = false
            presentation.routeAfterDismissal(destination: .addMiner)
            XCTAssertFalse(presentation.showingAddMiner)

            presentation.present()
            presentation.isPresented = false
            presentation.complete(.viewPlans)
            presentation.routeAfterDismissal(destination: destination)
            XCTAssertFalse(presentation.showingPlans)
            XCTAssertFalse(presentation.showingAddMiner)
        }
    }
}
