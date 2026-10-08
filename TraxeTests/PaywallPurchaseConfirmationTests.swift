import XCTest

@testable import Traxe

@MainActor
final class PaywallPurchaseConfirmationTests: XCTestCase {
    func testVerifiedFreeUserCanPurchaseWithoutAnOverlapWarning() {
        let confirmation = PaywallPurchaseConfirmation()
        confirmation.activate()
        var decisions: [Bool] = []
        confirmation.request(plan: .free, hasCurrentResponse: true) { decisions.append($0) }
        XCTAssertEqual(decisions, [true])
        XCTAssertTrue(confirmation.permitsPurchases)
        XCTAssertFalse(confirmation.isPresented)
    }

    func testUnverifiedAndExistingPaidPlansRequireAnExplicitDecision() {
        for plan in [SubscriptionSnapshot.Plan.free, .miners5, .pro] {
            for proceed in [true, false] {
                let confirmation = PaywallPurchaseConfirmation()
                confirmation.activate()
                var decisions: [Bool] = []
                confirmation.request(plan: plan, hasCurrentResponse: plan != .free) {
                    decisions.append($0)
                }
                XCTAssertTrue(decisions.isEmpty)
                XCTAssertTrue(confirmation.isPresented)
                XCTAssertTrue(confirmation.message.contains("won’t cancel"))
                confirmation.resolve(shouldProceed: proceed)
                confirmation.resolve(shouldProceed: !proceed)
                XCTAssertEqual(decisions, [proceed])
                XCTAssertEqual(confirmation.permitsPurchases, proceed)
                XCTAssertFalse(confirmation.isPresented)
            }
        }
    }

    func testClosingPaywallCancelsPendingPurchaseAndRejectsLateCallbacks() {
        let confirmation = PaywallPurchaseConfirmation()
        confirmation.activate()
        var decisions: [Bool] = []
        confirmation.request(plan: .pro, hasCurrentResponse: false) { decisions.append($0) }
        confirmation.deactivate()
        confirmation.resolve(shouldProceed: true)
        confirmation.request(plan: .free, hasCurrentResponse: true) { decisions.append($0) }
        XCTAssertEqual(decisions, [false, false])
        XCTAssertFalse(confirmation.permitsPurchases)
        XCTAssertFalse(confirmation.isPresented)
    }

    func testRepeatedPurchaseTapCannotReplacePendingDecision() {
        let confirmation = PaywallPurchaseConfirmation()
        confirmation.activate()
        var first: [Bool] = []
        var second: [Bool] = []
        confirmation.request(plan: .pro, hasCurrentResponse: true) { first.append($0) }
        confirmation.request(plan: .pro, hasCurrentResponse: true) { second.append($0) }
        XCTAssertTrue(first.isEmpty)
        XCTAssertEqual(second, [false])
        confirmation.resolve(shouldProceed: true)
        XCTAssertEqual(first, [true])
    }
}
