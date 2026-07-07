import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import Traxe

/// Render coverage for the single two-column `NavigationSplitView` that `DeviceListView`
/// uses at every width.
///
/// The horizontal size class is overridden on the hosting controller rather than in the
/// SwiftUI environment, so `NavigationSplitView` really collapses and expands instead of
/// only the surrounding layout changing.
@MainActor
final class DeviceListNavigationRenderTests: XCTestCase {
    func testRenderAdaptiveNavigationStatesAcrossCompactWideAndSquareLayouts() async throws {
        let previousPreviewEnvironmentValue = ProcessInfo.processInfo.environment[
            "XCODE_RUNNING_FOR_PREVIEWS"
        ]
        setenv("XCODE_RUNNING_FOR_PREVIEWS", "1", 1)
        UIView.setAnimationsEnabled(false)
        defer {
            UIView.setAnimationsEnabled(true)
            if let previousPreviewEnvironmentValue {
                previousPreviewEnvironmentValue.withCString { value in
                    setenv("XCODE_RUNNING_FOR_PREVIEWS", value, 1)
                }
            } else {
                unsetenv("XCODE_RUNNING_FOR_PREVIEWS")
            }
        }

        let suiteName = "navigation.device-list.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            try JSONEncoder().encode(PreviewFixtures.sampleSavedDevices),
            forKey: "savedDevices"
        )
        defaults.set(WhatsNewConfig.currentWhatsNewKey(), forKey: "lastSeenWhatsNewVersion")

        let dashboardContext = PreviewFixtures.makeDashboardPreviewContext()
        let dependencies = DeviceListViewModel.Dependencies(
            deviceManagement: .init(
                checkDevice: { ipAddress in
                    guard let metrics = PreviewFixtures.sampleDeviceMetricsByIP[ipAddress] else {
                        throw DeviceCheckError.requestFailed(.timedOut)
                    }
                    return DiscoveredDevice(
                        ip: ipAddress,
                        name: metrics.hostname ?? ipAddress,
                        hashrate: metrics.hashrate,
                        temperature: metrics.temperature,
                        bestDiff: "\(metrics.bestDifficulty)",
                        power: metrics.power,
                        poolURL: metrics.poolURL,
                        blockHeight: metrics.blockHeight,
                        networkDifficulty: metrics.networkDifficulty
                    )
                },
                deleteDevice: { _ in },
                reorderDevices: { _ in }
            ),
            reloadWidget: {},
            autoRefreshOnLoad: false
        )

        struct Step {
            let horizontalSizeClass: UIUserInterfaceSizeClass
            let size: CGSize
            let fileName: String?
        }

        struct Scenario {
            let navigationState: DeviceListNavigationState
            let steps: [Step]
        }

        let compactSize = CGSize(width: 402, height: 874)
        let wideSize = CGSize(width: 1_194, height: 834)
        let squareSize = CGSize(width: 900, height: 900)
        let selectedMiner = DeviceListNavigationState(
            selectedFeature: .miner(ipAddress: PreviewFixtures.sampleSecondaryDeviceID),
            preferredCompactColumn: .detail
        )

        let scenarios: [Scenario] = [
            Scenario(
                navigationState: DeviceListNavigationState(),
                steps: [
                    Step(
                        horizontalSizeClass: .compact,
                        size: compactSize,
                        fileName: "N1_compact-dashboard.png"
                    )
                ]
            ),
            Scenario(
                navigationState: selectedMiner,
                steps: [
                    Step(
                        horizontalSizeClass: .compact,
                        size: compactSize,
                        fileName: "N2_compact-miner-detail.png"
                    )
                ]
            ),
            Scenario(
                navigationState: selectedMiner,
                steps: [
                    Step(
                        horizontalSizeClass: .regular,
                        size: wideSize,
                        fileName: "N3_wide-dashboard-and-miner.png"
                    )
                ]
            ),
            Scenario(
                navigationState: selectedMiner,
                steps: [
                    Step(
                        horizontalSizeClass: .regular,
                        size: squareSize,
                        fileName: "N4_square-dashboard-and-miner.png"
                    )
                ]
            ),
            Scenario(
                navigationState: DeviceListNavigationState(
                    selectedFeature: .fleetRecap,
                    preferredCompactColumn: .detail
                ),
                steps: [
                    Step(
                        horizontalSizeClass: .regular,
                        size: wideSize,
                        fileName: "N5_wide-dashboard-and-fleet-recap.png"
                    )
                ]
            ),
            // One live scene that collapses, expands, then collapses again without being
            // rebuilt, so the captures show whether the selection survives the round trip.
            Scenario(
                navigationState: selectedMiner,
                steps: [
                    Step(
                        horizontalSizeClass: .compact,
                        size: compactSize,
                        fileName: "N6a_resize-compact-before.png"
                    ),
                    Step(
                        horizontalSizeClass: .regular,
                        size: wideSize,
                        fileName: "N6b_resize-wide.png"
                    ),
                    Step(
                        horizontalSizeClass: .compact,
                        size: compactSize,
                        fileName: "N6c_resize-compact-after.png"
                    ),
                ]
            ),
        ]

        var capturedImageData: [String: Data] = [:]

        for scenario in scenarios {
            let content = DeviceListView(
                dashboardViewModel: dashboardContext.viewModel,
                navigateToDeviceList: .constant(true),
                mockUserDefaults: defaults,
                viewModelDependencies: dependencies,
                initialNavigationState: scenario.navigationState
            )
            .modelContainer(dashboardContext.container)
            .environment(\.dynamicTypeSize, .medium)
            .environment(\.locale, Locale(identifier: "en_US"))
            .preferredColorScheme(.dark)

            let host = UIHostingController(rootView: content)
            host.overrideUserInterfaceStyle = .dark

            let firstStep = try XCTUnwrap(scenario.steps.first)
            let window: UIWindow
            if let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first
            {
                window = UIWindow(windowScene: scene)
            } else {
                window = UIWindow(frame: CGRect(origin: .zero, size: firstStep.size))
            }
            window.overrideUserInterfaceStyle = .dark
            window.rootViewController = host
            window.makeKeyAndVisible()

            for step in scenario.steps {
                host.traitOverrides.horizontalSizeClass = step.horizontalSizeClass
                window.frame = CGRect(origin: .zero, size: step.size)
                host.view.frame = window.bounds
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(900))
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()

                guard let fileName = step.fileName else { continue }

                let format = UIGraphicsImageRendererFormat()
                format.scale = 2
                format.opaque = true
                let renderer = UIGraphicsImageRenderer(size: step.size, format: format)
                let image = renderer.image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let data = try XCTUnwrap(image.pngData(), "Failed to encode \(fileName)")
                capturedImageData[fileName] = data

                let attachment = XCTAttachment(
                    data: data,
                    uniformTypeIdentifier: "public.png"
                )
                attachment.name = fileName
                attachment.lifetime = .keepAlways
                add(attachment)
            }

            window.isHidden = true
        }

        XCTAssertEqual(capturedImageData.count, 8)

        let compactDashboard = try XCTUnwrap(capturedImageData["N1_compact-dashboard.png"])
        let compactMinerDetail = try XCTUnwrap(capturedImageData["N2_compact-miner-detail.png"])
        let resizeCompactAfter = try XCTUnwrap(capturedImageData["N6c_resize-compact-after.png"])

        // A selected miner collapses to the detail column, not to the dashboard.
        XCTAssertNotEqual(compactDashboard, compactMinerDetail)
        // Collapsing, expanding, and collapsing again keeps the miner on screen instead of
        // falling back to the dashboard.
        XCTAssertNotEqual(compactDashboard, resizeCompactAfter)
    }
}
