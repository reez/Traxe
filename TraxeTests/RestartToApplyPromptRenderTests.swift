import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import Traxe

/// Visual QA for the restart prompt shown after a pool or hostname save on firmware that only
/// applies those settings while booting (ESP-Miner before 2.15), next to the Pool Settings
/// screen the save starts from. Off by default so ordinary test runs stay fast.
@MainActor
final class RestartToApplyPromptRenderTests: XCTestCase {
    func testRenderRestartToApplyPromptStates() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            environment["RENDER_RESTART_TO_APPLY_PROMPT"] == "1"
                || environment["TEST_RUNNER_RENDER_RESTART_TO_APPLY_PROMPT"] == "1"
        else {
            throw XCTSkip("Set RENDER_RESTART_TO_APPLY_PROMPT=1 to render visual QA states.")
        }

        // Keeps the rendered app code on its preview path: no RevenueCat, no networking.
        setenv("XCODE_RUNNING_FOR_PREVIEWS", "1", 1)
        UIView.setAnimationsEnabled(false)
        addTeardownBlock {
            unsetenv("XCODE_RUNNING_FOR_PREVIEWS")
            UIView.setAnimationsEnabled(true)
        }

        let outputDirectory = URL(
            fileURLWithPath: environment["RESTART_TO_APPLY_PROMPT_DIR"]
                ?? environment["TEST_RUNNER_RESTART_TO_APPLY_PROMPT_DIR"]
                ?? "screenshots/visual-qa/restart-to-apply-prompt"
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let size = CGSize(width: 393, height: 852)
        let schema = Schema([HistoricalDataPoint.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )

        let states: [(filename: String, isHostname: Bool, showsPrompt: Bool)] = [
            ("01-pool-settings-before-save.png", false, false),
            ("02-pool-settings-restart-prompt.png", false, true),
            ("03-hostname-restart-prompt.png", true, true),
        ]

        for state in states {
            let suiteName = "RestartToApplyPromptRenderTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defaults.removePersistentDomain(forName: suiteName)
            addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set("192.168.1.100", forKey: "bitaxeIPAddress")

            // ESP-Miner 2.14: flat pool settings, no pool catalog, no active pool selector.
            let viewModel = SettingsViewModel(
                sharedUserDefaults: defaults,
                modelContext: container.mainContext,
                shouldFetchDeviceSettingsOnLoad: false
            )
            viewModel.currentVersion = "v2.14.0"
            viewModel.isConnected = true
            viewModel.hostname = "bitaxe-601"
            viewModel.stratumURL = "solo.ckpool.org"
            viewModel.stratumPortString = "3333"
            viewModel.stratumUser = "bc1qexample.primary"
            viewModel.fallbackStratumURL = "backup.pool.example"
            viewModel.fallbackStratumPortString = "4333"
            viewModel.fallbackStratumUser = "bc1qexample.backup"
            viewModel.needsRestartToApplySettings = state.showsPrompt

            let host = UIHostingController(
                rootView: NavigationStack {
                    if state.isHostname {
                        HostnameConfigurationView(viewModel: viewModel)
                    } else {
                        PoolConfigurationView(viewModel: viewModel)
                    }
                }
            )
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            // The alert is presented on a later run loop turn than the first layout.
            try await Task.sleep(for: .milliseconds(1_000))
            host.view.layoutIfNeeded()
            XCTAssertEqual(
                host.presentedViewController != nil,
                state.showsPrompt,
                "\(state.filename) should \(state.showsPrompt ? "" : "not ")present the restart alert"
            )

            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            format.opaque = true
            let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let pngData = try XCTUnwrap(rendered.pngData())
            try pngData.write(to: outputDirectory.appendingPathComponent(state.filename))
            window.isHidden = true
        }
    }
}
