import RevenueCat
import SwiftUI
import UIKit
import XCTest

@_spi(Internal) @testable import RevenueCatUI
@testable import Traxe

@MainActor
final class LoadedPaywallRenderTests: XCTestCase {
    func testRenderLoadedFallbackInsideActualPaywallScreen() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            environment["RENDER_RELIABILITY_RECOVERY"] == "1"
                || environment["TEST_RUNNER_RENDER_RELIABILITY_RECOVERY"] == "1"
        else { throw XCTSkip("Opt in to render the loaded paywall screen.") }
        let offering = Offering(
            identifier: "miners_5",
            serverDescription: "Traxe Miners 5",
            availablePackages: [
                Package(
                    identifier: "monthly", packageType: .monthly,
                    storeProduct: TestStoreProduct(
                        localizedTitle: "Traxe Miners 5", price: 1, currencyCode: "USD",
                        localizedPriceString: "$1.00", productIdentifier: "traxe.render.plan",
                        productType: .autoRenewableSubscription,
                        localizedDescription: "Monitor up to five miners",
                        subscriptionPeriod: .init(value: 1, unit: .month),
                        locale: Locale(identifier: "en_US")
                    ).toStoreProduct(),
                    offeringIdentifier: "miners_5", webCheckoutUrl: nil
                )
            ],
            webCheckoutUrl: nil
        )
        let json = Data("""
            {
              "request_date": "2026-09-28T10:30:42Z",
              "subscriber": {
                "first_seen": "2026-09-01T00:00:00Z",
                "original_app_user_id": "paywall-render-test",
                "subscriptions": {},
                "non_subscriptions": {},
                "entitlements": {}
              }
            }
            """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let customerInfo = try decoder.decode(CustomerInfo.self, from: json)
        let sdkCreated = expectation(description: "The app loaded its actual SDK paywall")
        sdkCreated.assertForOverFulfill = false
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let size = scene.coordinateSpace.bounds.size
        let confirmation = PaywallPurchaseConfirmation()
        let subscriptionStatus = SubscriptionStatusViewModel(
            cachedSnapshot: { nil }, fetchCurrent: { throw URLError(.cannotConnectToHost) },
            updates: { AsyncStream { $0.finish() } }
        )
        let host = UIHostingController(
            rootView: Traxe.PaywallView(
                fetchOffering: { offering },
                purchaseConfirmation: confirmation,
                subscriptionStatus: subscriptionStatus,
                makePaywall: { loadedOffering in
                    sdkCreated.fulfill()
                    // This is RevenueCat's actual view. Isolate its service dependencies
                    // so rendering never requires StoreKit or changes the app's SDK cache.
                    return RevenueCatUI.PaywallView(
                        configuration: .init(
                            offering: loadedOffering,
                            customerInfo: customerInfo,
                            introEligibility: .init(isConfigured: true) { _ in [:] },
                            purchaseHandler: .mock(customerInfo)
                        )
                    )
                }
            )
            .frame(width: size.width, height: size.height)
        )
        host.overrideUserInterfaceStyle = .dark
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        await fulfillment(of: [sdkCreated], timeout: 3)
        try await Task.sleep(for: .milliseconds(800))
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: rendered)
        attachment.name = "loaded-paywall-overlap-warning"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertTrue(confirmation.isPresented)
        XCTAssertFalse(confirmation.permitsPurchases)
        confirmation.resolve(shouldProceed: true)
        XCTAssertTrue(confirmation.permitsPurchases)
        try await Task.sleep(for: .milliseconds(600))
        let enabledPaywall = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let enabledAttachment = XCTAttachment(image: enabledPaywall)
        enabledAttachment.name = "loaded-paywall-fallback-toolbar"
        enabledAttachment.lifetime = .keepAlways
        add(enabledAttachment)
    }
}
