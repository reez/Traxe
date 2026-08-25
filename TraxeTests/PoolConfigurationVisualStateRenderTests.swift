import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import Traxe

/// Visual QA for Pool Settings: the active pool picker on ESP-Miner v2.15, its disabled state
/// while no fallback pool is configured, and firmware that does not report the selector.
/// Off by default so ordinary test runs stay fast.
@MainActor
final class PoolConfigurationVisualStateRenderTests: XCTestCase {
    func testRenderPoolConfigurationStates() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            environment["RENDER_POOL_CONFIGURATION_VISUAL_STATES"] == "1"
                || environment["TEST_RUNNER_RENDER_POOL_CONFIGURATION_VISUAL_STATES"] == "1"
        else {
            throw XCTSkip(
                "Set RENDER_POOL_CONFIGURATION_VISUAL_STATES=1 to render visual QA states."
            )
        }

        // Keeps the rendered app code on its preview path: no RevenueCat, no networking.
        setenv("XCODE_RUNNING_FOR_PREVIEWS", "1", 1)
        UIView.setAnimationsEnabled(false)
        addTeardownBlock {
            unsetenv("XCODE_RUNNING_FOR_PREVIEWS")
            UIView.setAnimationsEnabled(true)
        }

        let outputDirectory = URL(
            fileURLWithPath: environment["POOL_CONFIGURATION_VISUAL_STATES_DIR"]
                ?? environment["TEST_RUNNER_POOL_CONFIGURATION_VISUAL_STATES_DIR"]
                ?? "screenshots/visual-qa/pool-configuration-states"
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let pointSize = CGSize(width: 393, height: 852)
        let scale: CGFloat = 3
        let schema = Schema([HistoricalDataPoint.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )

        let poolStates:
            [(
                filename: String, fallbackURL: String, supportsActivePoolSelection: Bool,
                useFallbackStratum: Bool
            )] = [
                (
                    "01-pool-settings-esp-miner-2-15-fallback-active.png", "eu.backup.example",
                    true, true
                ),
                ("02-pool-settings-esp-miner-2-15-no-fallback-pool.png", "", true, false),
                ("03-pool-settings-legacy-firmware.png", "eu.backup.example", false, false),
            ]

        for poolState in poolStates {
            let suiteName = "PoolConfigurationVisualStateRenderTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defaults.removePersistentDomain(forName: suiteName)
            addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set("192.168.1.100", forKey: "bitaxeIPAddress")

            let viewModel = SettingsViewModel(
                sharedUserDefaults: defaults,
                modelContext: container.mainContext,
                shouldFetchDeviceSettingsOnLoad: false
            )
            viewModel.currentVersion = "v2.15.0"
            viewModel.isConnected = true
            viewModel.stratumURL = "public-pool.io"
            viewModel.stratumPortString = "21496"
            viewModel.stratumUser = "bc1qexample.primary"
            viewModel.fallbackStratumURL = poolState.fallbackURL
            viewModel.fallbackStratumPortString = poolState.fallbackURL.isEmpty ? "" : "4444"
            viewModel.fallbackStratumUser =
                poolState.fallbackURL.isEmpty ? "" : "bc1qexample.backup"
            viewModel.supportsStratumProtocolSettings = true
            viewModel.stratumProtocol = "SV1"
            viewModel.fallbackStratumProtocol = "SV1"
            viewModel.supportsActivePoolSelection = poolState.supportsActivePoolSelection
            viewModel.useFallbackStratum = poolState.useFallbackStratum

            let host = UIHostingController(
                rootView: NavigationStack { PoolConfigurationView(viewModel: viewModel) }
                    .frame(width: pointSize.width, height: pointSize.height)
            )
            host.overrideUserInterfaceStyle = .dark

            let window: UIWindow
            if let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first
            {
                window = UIWindow(windowScene: scene)
            } else {
                window = UIWindow(frame: CGRect(origin: .zero, size: pointSize))
            }

            window.frame = CGRect(origin: .zero, size: pointSize)
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            host.view.backgroundColor = .black
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()

            try await Task.sleep(for: .milliseconds(600))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()

            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: pointSize, format: format)
            let image = renderer.image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }

            let data = try XCTUnwrap(image.pngData(), "Failed to render \(poolState.filename)")
            let outputURL = outputDirectory.appendingPathComponent(poolState.filename)
            try data.write(to: outputURL, options: [.atomic])
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

            window.isHidden = true
        }
    }
}
