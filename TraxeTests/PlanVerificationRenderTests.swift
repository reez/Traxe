import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import Traxe

@MainActor
final class PlanVerificationRenderTests: XCTestCase {
    func testRenderUnverifiedPlanBeforeAddingAnotherMiner() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            environment["RENDER_RELIABILITY_RECOVERY"] == "1"
                || environment["TEST_RUNNER_RENDER_RELIABILITY_RECOVERY"] == "1"
        else { throw XCTSkip("Opt in to render the plan verification view.") }
        let status = SubscriptionStatusViewModel(
            cachedSnapshot: { nil },
            fetchCurrent: { throw URLError(.notConnectedToInternet) }
        )
        await status.refresh()
        XCTAssertEqual(status.addMinerDestination(savedDeviceCount: 1), .verifyPlan)
        let size = CGSize(width: 393, height: 852)
        let host = UIHostingController(
            rootView: PlanVerificationView(
                subscriptionStatus: status, savedDeviceCount: 1, onVerified: {}, onViewPlans: {}
            )
            .frame(width: size.width, height: size.height)
        )
        host.overrideUserInterfaceStyle = .dark
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(600))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: rendered)
        attachment.name = "plan-verification-before-add"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testRenderRestoreInProgressAfterVerificationFailure() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            environment["RENDER_RELIABILITY_RECOVERY"] == "1"
                || environment["TEST_RUNNER_RENDER_RELIABILITY_RECOVERY"] == "1"
        else { throw XCTSkip("Opt in to render restore progress.") }
        let status = SubscriptionStatusViewModel(
            cachedSnapshot: { nil },
            fetchCurrent: { throw URLError(.cannotConnectToHost) }
        )
        await status.refresh()
        var finishRestore: CheckedContinuation<Bool, Never>?
        let restore = RestorePurchasesViewModel(restorePurchases: {
            await withCheckedContinuation { finishRestore = $0 }
        })
        let restoreTask = Task { await restore.restore() }
        while finishRestore == nil { await Task.yield() }
        XCTAssertTrue(restore.isRestoring)
        defer { finishRestore?.resume(returning: false) }
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let size = scene.coordinateSpace.bounds.size
        let host = UIHostingController(
            rootView: PlanVerificationView(
                subscriptionStatus: status, savedDeviceCount: 1,
                onVerified: {}, onViewPlans: {}, restoreViewModel: restore
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
        try await Task.sleep(for: .milliseconds(600))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: rendered)
        attachment.name = "plan-verification-restoring"
        attachment.lifetime = .keepAlways
        add(attachment)
        finishRestore?.resume(returning: false)
        finishRestore = nil
        _ = await restoreTask.value
    }

    func testRenderSettingsWithUnavailablePlan() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            environment["RENDER_RELIABILITY_RECOVERY"] == "1"
                || environment["TEST_RUNNER_RENDER_RELIABILITY_RECOVERY"] == "1"
        else { throw XCTSkip("Opt in to render Settings with an unavailable plan.") }
        let schema = Schema([HistoricalDataPoint.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let suite = "PlanVerificationRenderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("192.168.1.100", forKey: "bitaxeIPAddress")
        let settings = SettingsViewModel(
            sharedUserDefaults: defaults,
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false
        )
        settings.currentVersion = "v2.6.0"
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let size = scene.coordinateSpace.bounds.size
        let host = UIHostingController(
            rootView: ScrollViewReader { proxy in
                SettingsView(viewModel: settings)
                    .environment(\.previewUpgradeState, .unavailable)
                    .modelContainer(container)
                    .task {
                        try? await Task.sleep(for: .milliseconds(300))
                        proxy.scrollTo("unavailable-plan", anchor: .center)
                    }
            }
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
        try await Task.sleep(for: .milliseconds(700))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: rendered)
        attachment.name = "settings-plan-unavailable"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
