import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import Traxe

/// Visual QA for the ESP-Miner v2.15 Pool Settings screen: the primary slot selected (delete
/// disabled) and a spare slot selected (delete enabled). Off by default so ordinary test runs
/// stay fast.
@MainActor
final class PoolCatalogVisualStateRenderTests: XCTestCase {
    func testRenderPoolCatalogStates() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            environment["RENDER_POOL_CATALOG_VISUAL_STATES"] == "1"
                || environment["TEST_RUNNER_RENDER_POOL_CATALOG_VISUAL_STATES"] == "1"
        else {
            throw XCTSkip("Set RENDER_POOL_CATALOG_VISUAL_STATES=1 to render visual QA states.")
        }

        // Keeps the rendered app code on its preview path: no RevenueCat, no networking.
        setenv("XCODE_RUNNING_FOR_PREVIEWS", "1", 1)
        UIView.setAnimationsEnabled(false)
        addTeardownBlock {
            unsetenv("XCODE_RUNNING_FOR_PREVIEWS")
            UIView.setAnimationsEnabled(true)
        }

        let outputDirectory = URL(
            fileURLWithPath: environment["POOL_CATALOG_VISUAL_STATES_DIR"]
                ?? environment["TEST_RUNNER_POOL_CATALOG_VISUAL_STATES_DIR"]
                ?? "screenshots/visual-qa/pool-catalog-states"
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        // Taller than a phone so the Delete and Save rows below the fold are captured too.
        let pointSize = CGSize(width: 393, height: 1300)
        let scale: CGFloat = 3
        let schema = Schema([HistoricalDataPoint.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )

        let states: [(filename: String, selectedSlotID: Int)] = [
            ("01-pool-catalog-primary-slot-selected.png", 0),
            ("02-pool-catalog-spare-slot-selected.png", 2),
        ]

        for state in states {
            let suiteName = "PoolCatalogVisualStateRenderTests.\(UUID().uuidString)"
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
            viewModel.supportsStratumProtocolSettings = true
            viewModel.supportsActivePoolSelection = true
            viewModel.supportsMultiPoolSettings = true
            var publicPool = PoolSlotDraft(id: 0)
            publicPool.stratumURL = "public-pool.io"
            publicPool.stratumPortString = "3333"
            publicPool.stratumUser = "bc1qexample.primary"
            publicPool.stratumProtocol = "SV2"
            publicPool.stratumV2ChannelType = "extended"
            publicPool.stratumV2AuthorityPubkey =
                "9c4zpyJ2ndm4e8sP2uNc1VNCGxYjqaxWS6wUCjk8zFj6njFquH6"
            var ckpool = PoolSlotDraft(id: 1)
            ckpool.stratumURL = "solo.ckpool.org"
            ckpool.stratumPortString = "3333"
            ckpool.stratumUser = "bc1qexample.backup"
            var ocean = PoolSlotDraft(id: 2)
            ocean.stratumURL = "mine.ocean.xyz"
            ocean.stratumPortString = "3334"
            ocean.stratumUser = "bc1qexample.spare"
            viewModel.poolCatalog = PoolCatalogDraft(
                slots: [publicPool, ckpool, ocean],
                primaryPoolID: 0,
                secondaryPoolID: 1,
                useFallbackStratum: false
            )

            let host = UIHostingController(
                rootView: NavigationStack {
                    PoolCatalogView(
                        viewModel: viewModel,
                        initialSelectedSlotID: state.selectedSlotID
                    )
                }
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

            let data = try XCTUnwrap(image.pngData(), "Failed to render \(state.filename)")
            let outputURL = outputDirectory.appendingPathComponent(state.filename)
            try data.write(to: outputURL, options: [.atomic])
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

            window.isHidden = true
        }
    }
}
