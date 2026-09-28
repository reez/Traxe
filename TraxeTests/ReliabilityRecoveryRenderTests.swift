import SwiftUI
import UIKit
import XCTest

@testable import Traxe

@MainActor
final class ReliabilityRecoveryRenderTests: XCTestCase {
    func testRenderPurchaseRecoveryAndQualifiedFleetReadings() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            environment["RENDER_RELIABILITY_RECOVERY"] == "1"
                || environment["TEST_RUNNER_RENDER_RELIABILITY_RECOVERY"] == "1"
        else { throw XCTSkip("Opt in to render reliability recovery views.") }
        let previousPreview = environment["XCODE_RUNNING_FOR_PREVIEWS"]
        setenv("XCODE_RUNNING_FOR_PREVIEWS", "1", 1)
        UIView.setAnimationsEnabled(false)
        defer {
            UIView.setAnimationsEnabled(true)
            if let previousPreview {
                setenv("XCODE_RUNNING_FOR_PREVIEWS", previousPreview, 1)
            } else {
                unsetenv("XCODE_RUNNING_FOR_PREVIEWS")
            }
        }
        let outcome = PaywallOutcomeViewModel(syncPurchase: { false })
        XCTAssertFalse(outcome.completePurchase(hasActivePlan: false))
        let restore = RestorePurchasesViewModel(restorePurchases: { false })
        var scenarios: [(String, AnyView)] = [
            (
                "purchase-verification",
                AnyView(
                    PaywallPurchaseRecoveryView(
                        outcome: outcome,
                        restoreViewModel: restore,
                        onRecovered: {}
                    )
                )
            )
        ]
        for partial in [false, true] {
            let suite = "ReliabilityRecoveryRenderTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
            let devices = [
                SavedDevice(name: "Office", ipAddress: "192.168.1.10"),
                SavedDevice(name: "Garage", ipAddress: "192.168.1.11"),
            ]
            defaults.set(try JSONEncoder().encode(devices), forKey: "savedDevices")
            let model = DeviceListViewModel(
                defaults: defaults,
                dependencies: .init(
                    deviceManagement: .init(
                        checkDevice: { ip in
                            guard partial, ip == "192.168.1.10" else {
                                throw URLError(.cannotConnectToHost)
                            }
                            return DiscoveredDevice(
                                ip: ip,
                                name: "Office",
                                hashrate: 600,
                                temperature: 50,
                                bestDiff: "2 M",
                                power: 12,
                                poolURL: nil,
                                blockHeight: nil,
                                networkDifficulty: nil
                            )
                        },
                        deleteDevice: { _ in },
                        reorderDevices: { _ in }
                    ),
                    reloadWidget: {},
                    autoRefreshOnLoad: false
                )
            )
            for device in devices {
                model.deviceMetrics[device.ipAddress] = DeviceMetrics(
                    hashrate: 600,
                    temperature: 50,
                    power: 12,
                    timestamp: Date().addingTimeInterval(-600)
                )
            }
            await model.updateAggregatedStats()
            XCTAssertEqual(model.fleetMetricSnapshot.isStale, !partial)
            XCTAssertEqual(model.totalHashRate, partial ? 600 : 1200)
            scenarios.append(
                (
                    partial ? "fleet-partial" : "fleet-stale",
                    AnyView(
                        ScrollView {
                            AggregatedStatsHeader(viewModel: model, showFleetWeeklyRecap: {})
                        }
                    )
                )
            )
        }
        let size = CGSize(width: 393, height: 852)
        for (name, view) in scenarios {
            let host = UIHostingController(
                rootView: view.frame(width: size.width, height: size.height)
            )
            host.overrideUserInterfaceStyle = .dark
            let scene = try XCTUnwrap(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            )
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            host.view.backgroundColor = .black
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(600))
            host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            format.opaque = true
            let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: rendered)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
        }
    }
}
