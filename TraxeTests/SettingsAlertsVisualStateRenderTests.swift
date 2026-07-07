import SwiftData
import SwiftUI
import UIKit
import UserNotifications
import XCTest

@testable import Traxe

/// Visual QA for the per-miner Alerts setting: the toggle, its footer, and the notification
/// permission warning. Off by default so ordinary test runs stay fast.
@MainActor
final class SettingsAlertsVisualStateRenderTests: XCTestCase {
    func testRenderMinerAlertsSettingStates() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            environment["RENDER_SETTINGS_ALERTS_VISUAL_STATES"] == "1"
                || environment["TEST_RUNNER_RENDER_SETTINGS_ALERTS_VISUAL_STATES"] == "1"
        else {
            throw XCTSkip("Set RENDER_SETTINGS_ALERTS_VISUAL_STATES=1 to render visual QA states.")
        }

        // Keeps the rendered app code on its preview path: no RevenueCat, no networking.
        setenv("XCODE_RUNNING_FOR_PREVIEWS", "1", 1)
        UIView.setAnimationsEnabled(false)
        addTeardownBlock {
            unsetenv("XCODE_RUNNING_FOR_PREVIEWS")
            UIView.setAnimationsEnabled(true)
        }

        let outputDirectory = URL(
            fileURLWithPath: environment["SETTINGS_ALERTS_VISUAL_STATES_DIR"]
                ?? environment["TEST_RUNNER_SETTINGS_ALERTS_VISUAL_STATES_DIR"]
                ?? "screenshots/visual-qa/miner-alerts-states"
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let pointSize = CGSize(width: 393, height: 852)
        let scale: CGFloat = 3
        let ipAddress = "192.168.1.100"
        let alertStates: [(filename: String, isEnabled: Bool, status: UNAuthorizationStatus)] = [
            ("01-miner-alerts-off.png", false, .notDetermined),
            ("02-miner-alerts-on.png", true, .authorized),
            ("03-miner-alerts-notifications-blocked.png", true, .denied),
        ]

        var scenarios: [(filename: String, view: AnyView)] = []
        for alertState in alertStates {
            let suiteName = "SettingsAlertsVisualStateRenderTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defaults.removePersistentDomain(forName: suiteName)
            addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }

            let preferences = MinerAlertPreferences(defaults: defaults)
            preferences.setEnabled(alertState.isEnabled, for: ipAddress)
            let status = alertState.status
            let viewModel = MinerAlertsSettingsViewModel(
                ipAddress: ipAddress,
                preferences: preferences,
                authorization: MinerAlertNotificationAuthorization(
                    currentStatus: { status },
                    requestAuthorization: { status }
                ),
                reloadWidgetTimelines: {}
            )
            scenarios.append(
                (
                    alertState.filename,
                    AnyView(Form { MinerAlertsSection(viewModel: viewModel) })
                )
            )
        }

        // The whole screen, so the section can be checked in the context it ships in.
        let schema = Schema([HistoricalDataPoint.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let settingsSuiteName = "SettingsAlertsVisualStateRenderTests.\(UUID().uuidString)"
        let settingsDefaults = try XCTUnwrap(UserDefaults(suiteName: settingsSuiteName))
        settingsDefaults.removePersistentDomain(forName: settingsSuiteName)
        addTeardownBlock {
            settingsDefaults.removePersistentDomain(forName: settingsSuiteName)
        }
        settingsDefaults.set(ipAddress, forKey: "bitaxeIPAddress")
        let settingsViewModel = SettingsViewModel(
            sharedUserDefaults: settingsDefaults,
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false
        )
        settingsViewModel.currentVersion = "v2.6.0"
        settingsViewModel.isConnected = true
        scenarios.append(
            (
                "04-settings-screen.png",
                AnyView(
                    SettingsView(viewModel: settingsViewModel)
                        .modelContainer(container)
                )
            )
        )

        for scenario in scenarios {
            let host = UIHostingController(
                rootView: scenario.view
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

            let data = try XCTUnwrap(image.pngData(), "Failed to render \(scenario.filename)")
            let outputURL = outputDirectory.appendingPathComponent(scenario.filename)
            try data.write(to: outputURL, options: [.atomic])
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

            window.isHidden = true
        }
    }
}
