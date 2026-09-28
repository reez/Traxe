import RevenueCat
import SwiftUI
import UIKit
import XCTest

@testable import RevenueCatUI
@testable import Traxe

@MainActor
final class PaywallCallbackIntegrationTests: XCTestCase {
    func testFallbackRestoreStartWithoutCompletionDoesNotBlockDismissal() async throws {
        let outcome = PaywallOutcomeViewModel(syncPurchase: { false })
        let started = expectation(description: "SDK delivered restore-start")
        var dismissals = 0
        struct FallbackRestoreEvent: View {
            @Environment(\.onRequestedDismissal) private var requestDismissal
            let onStarted: () -> Void

            var body: some View {
                Color.clear
                    .preference(key: RestoreInProgressPreferenceKey.self, value: true)
                    .onRestoreStarted {
                        requestDismissal?()
                        onStarted()
                    }
            }
        }
        let content = FallbackRestoreEvent(onStarted: { started.fulfill() })
            .modifier(PaywallEventModifier(outcome: outcome, dismiss: { dismissals += 1 }))
        let host = UIHostingController(rootView: content)
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        await fulfillment(of: [started], timeout: 2)

        XCTAssertFalse(outcome.isActionInProgress)
        XCTAssertTrue(outcome.permitsSDKDismissal)
        XCTAssertEqual(dismissals, 1)
    }

    func testSDKPurchaseStartBlocksDismissalUntilAnOutcomeArrives() async throws {
        let outcome = PaywallOutcomeViewModel(syncPurchase: { false })
        let package = Package(
            identifier: "monthly",
            packageType: .monthly,
            storeProduct: TestStoreProduct(
                localizedTitle: "Traxe plan", price: 1, currencyCode: "USD",
                localizedPriceString: "$1.00", productIdentifier: "callback-test",
                productType: .autoRenewableSubscription, localizedDescription: "Test plan",
                subscriptionPeriod: .init(value: 1, unit: .month),
                locale: Locale(identifier: "en_US")
            ).toStoreProduct(),
            offeringIdentifier: "test", webCheckoutUrl: nil
        )
        let started = expectation(description: "SDK delivered purchase-start")
        let content = Color.clear
            .preference(key: PurchaseInProgressPreferenceKey.self, value: package)
            .modifier(PaywallEventModifier(outcome: outcome, dismiss: {}))
            .onPurchaseStarted { _ in started.fulfill() }
        let host = UIHostingController(rootView: content)
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        await fulfillment(of: [started], timeout: 2)

        XCTAssertTrue(outcome.isActionInProgress)
        XCTAssertFalse(outcome.permitsSDKDismissal)
    }

    func testSDKCompletionCancellationAndFailureEventsReachPaywallState() async throws {
        let json = Data("""
            {
              "request_date": "2026-09-28T10:30:42Z",
              "subscriber": {
                "first_seen": "2026-09-01T00:00:00Z",
                "original_app_user_id": "callback-test",
                "subscriptions": {},
                "non_subscriptions": {},
                "entitlements": {}
              }
            }
            """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let info = try decoder.decode(CustomerInfo.self, from: json)
        for event in ["purchase", "cancel", "purchase-failure", "restore", "restore-failure"] {
            let outcome = PaywallOutcomeViewModel(syncPurchase: { false })
            outcome.beginAction()
            var dismissals = 0
            let delivered = expectation(description: "SDK delivered \(event)")
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
            let content = Color.clear
                .preference(
                    key: PurchasedResultPreferenceKey.self,
                    value: event == "purchase" || event == "cancel"
                        ? .init(data: (nil, info, event == "cancel")) : nil
                )
                .preference(
                    key: RestoredCustomerInfoPreferenceKey.self,
                    value: event == "restore" ? .init(customerInfo: info, success: false) : nil
                )
                .preference(key: PurchaseErrorPreferenceKey.self,
                            value: event == "purchase-failure" ? error : nil)
                .preference(key: RestoreErrorPreferenceKey.self,
                            value: event == "restore-failure" ? error : nil)
                .modifier(PaywallEventModifier(outcome: outcome, dismiss: { dismissals += 1 }))
                .onPurchaseCompleted { _ in delivered.fulfill() }
                .onPurchaseCancelled { delivered.fulfill() }
                .onPurchaseFailure { _ in delivered.fulfill() }
                .onRestoreCompleted { _ in delivered.fulfill() }
                .onRestoreFailure { _ in delivered.fulfill() }
            let host = UIHostingController(rootView: content)
            let scene = try XCTUnwrap(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            )
            let window = UIWindow(windowScene: scene)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }

            await fulfillment(of: [delivered], timeout: 2)

            XCTAssertFalse(outcome.isActionInProgress, event)
            XCTAssertEqual(outcome.purchaseNeedsRecovery, event == "purchase", event)
            XCTAssertEqual(outcome.showingRestoreMessage, event == "restore", event)
            XCTAssertEqual(outcome.permitsSDKDismissal,
                           event != "purchase" && event != "restore", event)
            XCTAssertEqual(dismissals, 0, event)
        }
    }

    func testFallbackStyleControlsStayDisabledUntilWarningAcknowledged() async throws {
        let status = SubscriptionStatusViewModel(
            cachedSnapshot: { nil }, fetchCurrent: { throw URLError(.cannotConnectToHost) },
            updates: { AsyncStream { $0.finish() } }
        )
        await status.refresh()
        let confirmation = PaywallPurchaseConfirmation()
        let disabled = expectation(description: "Paywall controls start disabled")
        let enabled = expectation(description: "Acknowledgement enables paywall controls")
        var states: [Bool] = []
        var cancellations = 0
        struct PaywallControls: View {
            @Environment(\.isEnabled) private var isEnabled
            let changed: (Bool) -> Void
            var body: some View {
                Button("Purchase") {}
                    .onChange(of: isEnabled, initial: true) { _, value in changed(value) }
            }
        }
        let content = PaywallControls { value in
            states.append(value)
            if value { enabled.fulfill() } else { disabled.fulfill() }
        }
        .modifier(PaywallPurchaseConfirmationModifier(
            subscriptionStatus: status, confirmation: confirmation,
            onCancelled: { cancellations += 1 }
        ))
        let host = UIHostingController(rootView: content)
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await fulfillment(of: [disabled], timeout: 3)
        XCTAssertTrue(confirmation.isPresented)
        XCTAssertEqual(states, [false])
        XCTAssertFalse(confirmation.permitsPurchases)
        confirmation.resolve(shouldProceed: true)
        await fulfillment(of: [enabled], timeout: 3)
        XCTAssertEqual(states, [false, true])
        XCTAssertEqual(cancellations, 0)
    }
}
