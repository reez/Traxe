import SwiftUI
import UIKit
import XCTest

@testable import Traxe

/// Lifecycle coverage for the miner detail screen's AI summary.
///
/// The real `DeviceSummaryView` runs in a window so the generating dots, the typewriter
/// reveal, and the `task` lifecycle behave exactly as they do in the app; only summary
/// generation is injected so the run is deterministic.
@MainActor
final class DeviceSummaryAISummaryLifecycleRenderTests: XCTestCase {

    func testOneScreenVisitGeneratesTheSummaryOnceAndSettlesWithoutRestarting() async throws {
        final class RequestLog: @unchecked Sendable {
            private let lock = NSLock()
            private var storage: [String] = []

            var deviceIPs: [String] {
                lock.lock()
                defer { lock.unlock() }
                return storage
            }

            func record(_ deviceIP: String) {
                lock.lock()
                storage.append(deviceIP)
                lock.unlock()
            }
        }

        let previousAIEnabledValue = UserDefaults.standard.bool(forKey: "ai_enabled")
        UserDefaults.standard.set(true, forKey: "ai_enabled")
        defer {
            UserDefaults.standard.set(previousAIEnabledValue, forKey: "ai_enabled")
        }

        let deviceIP = PreviewFixtures.sampleSecondaryDeviceID
        let summaryContent = "Averaging 720 GH/s over the last 24 hours at a steady 64°C."
        let requests = RequestLog()
        let controller = DeviceAISummaryController(
            dependencies: .init(startDelay: .milliseconds(900)) { requestedDeviceIP, _ in
                requests.record(requestedDeviceIP)
                try await Task.sleep(for: .milliseconds(600))
                return AISummary(content: summaryContent)
            }
        )

        let dashboardContext = PreviewFixtures.makeDashboardPreviewContext(deviceId: deviceIP)
        let content = NavigationStack {
            DeviceSummaryView(
                dashboardViewModel: dashboardContext.viewModel,
                deviceName: "bitaxe",
                deviceIP: deviceIP,
                poolName: "publicpool.io",
                summaryController: controller
            )
        }
        .modelContainer(dashboardContext.container)
        .environment(\.dynamicTypeSize, .medium)
        .environment(\.locale, Locale(identifier: "en_US"))
        .preferredColorScheme(.dark)

        let size = CGSize(width: 402, height: 874)
        let host = UIHostingController(rootView: content)
        host.overrideUserInterfaceStyle = .dark

        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first
        {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: size))
        }
        window.overrideUserInterfaceStyle = .dark
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.backgroundColor = .black
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        // The screen runs untouched first so the generating dots, the crossfade, and the
        // typewriter reveal play at their real cadence, with a layout round trip partway
        // through generation to replay the lifecycle events a collapsing detail column
        // fires while a request is already running.
        try await Task.sleep(for: .milliseconds(1_000))
        host.traitOverrides.horizontalSizeClass = .regular
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        host.traitOverrides.horizontalSizeClass = .compact
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(5_800))

        // Three captures once the reveal has finished. Rendering is expensive enough to
        // disturb the animation, so it only happens after the screen should be settled.
        var settledFrames: [Data] = []
        for frameIndex in 0..<3 {
            let image = renderer.image { context in
                host.view.layer.render(in: context.cgContext)
            }
            let data = try XCTUnwrap(image.pngData(), "Failed to encode frame \(frameIndex)")
            settledFrames.append(data)

            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = String(format: "summary-settled-%02d.png", frameIndex)
            attachment.lifetime = .keepAlways
            add(attachment)

            try await Task.sleep(for: .milliseconds(400))
        }

        window.isHidden = true

        // One visit, one request, one published summary, even across the layout round trip.
        XCTAssertEqual(requests.deviceIPs, [deviceIP])
        XCTAssertEqual(controller.summary?.content, summaryContent)
        XCTAssertFalse(controller.isGenerating)
        if case .connected = dashboardContext.viewModel.connectionState {
            // The detail screen must preserve the list's established connection so the
            // Stats grid never returns to its redacted loading state behind the summary.
        } else {
            XCTFail("Presenting the detail screen restarted or lost the existing connection")
        }

        // The screen has stopped changing by the end, so nothing is still re-revealing or
        // restarting the summary behind the settled text. The first capture can still include
        // the tail of SwiftUI's section crossfade; the final two must be identical.
        XCTAssertEqual(settledFrames[1], settledFrames[2])
    }

    func testLeavingAndReturningToTheScreenDoesNotReplayTheSummaryReveal() async throws {
        final class RequestLog: @unchecked Sendable {
            private let lock = NSLock()
            private var storage: [String] = []

            var deviceIPs: [String] {
                lock.lock()
                defer { lock.unlock() }
                return storage
            }

            func record(_ deviceIP: String) {
                lock.lock()
                storage.append(deviceIP)
                lock.unlock()
            }
        }

        let previousAIEnabledValue = UserDefaults.standard.bool(forKey: "ai_enabled")
        UserDefaults.standard.set(true, forKey: "ai_enabled")
        defer {
            UserDefaults.standard.set(previousAIEnabledValue, forKey: "ai_enabled")
        }

        let deviceIP = PreviewFixtures.sampleSecondaryDeviceID
        // Long enough that a replayed reveal is still visibly unfinished when the assertions
        // run: 118 characters is roughly six seconds of typing.
        let summaryContent =
            "Averaging 720 GH/s over the last 24 hours at a steady 64°C. Solo odds to hit a block are 1 in 13.1M today."
        let requests = RequestLog()
        let controller = DeviceAISummaryController(
            dependencies: .init(startDelay: .milliseconds(300)) { requestedDeviceIP, _ in
                requests.record(requestedDeviceIP)
                try await Task.sleep(for: .milliseconds(200))
                return AISummary(content: summaryContent)
            }
        )

        let dashboardContext = PreviewFixtures.makeDashboardPreviewContext(deviceId: deviceIP)
        // Pushing a destination over the detail screen is the app's own Weekly Recap
        // navigation, and it is what really disappears and re-presents the summary: the
        // screen's `task` modifiers are canceled and run again while its state survives.
        func content(pushedPath: [String]) -> some View {
            NavigationStack(path: .constant(pushedPath)) {
                DeviceSummaryView(
                    dashboardViewModel: dashboardContext.viewModel,
                    deviceName: "bitaxe",
                    deviceIP: deviceIP,
                    poolName: "publicpool.io",
                    summaryController: controller
                )
                .navigationDestination(for: String.self) { _ in
                    Color.black.ignoresSafeArea()
                }
            }
            .modelContainer(dashboardContext.container)
            .environment(\.dynamicTypeSize, .medium)
            .environment(\.locale, Locale(identifier: "en_US"))
            .preferredColorScheme(.dark)
        }

        let size = CGSize(width: 402, height: 874)
        let host = UIHostingController(rootView: content(pushedPath: []))
        host.overrideUserInterfaceStyle = .dark

        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first
        {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: size))
        }
        window.overrideUserInterfaceStyle = .dark
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.backgroundColor = .black
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        // The toolbar button repaints its material when the pushed screen pops, so compare
        // only the fixed region containing the Summary heading and its typewriter text.
        let summaryRegion = CGRect(
            x: 0,
            y: 140 * format.scale,
            width: size.width * format.scale,
            height: 220 * format.scale
        )
        let captureSummaryContent: () -> Data? = {
            let screen = renderer.image { context in
                host.view.layer.render(in: context.cgContext)
            }
            guard let cropped = screen.cgImage?.cropping(to: summaryRegion) else { return nil }
            return UIImage(cgImage: cropped).pngData()
        }

        // Partway through the reveal, so the comparisons below are known to be looking at
        // text that actually changes rather than at an empty region.
        try await Task.sleep(for: .milliseconds(1_500))
        let revealingContent = try XCTUnwrap(captureSummaryContent())

        // Leaving and returning during the reveal: the summary may finish early, but it must
        // never start over.
        host.rootView = content(pushedPath: ["weekly-recap"])
        try await Task.sleep(for: .milliseconds(900))
        host.rootView = content(pushedPath: [])
        try await Task.sleep(for: .milliseconds(6_500))

        // A partly typed summary must not look like the finished one, otherwise the
        // comparison below could pass without ever observing the reveal.
        let settledContent = try XCTUnwrap(captureSummaryContent())
        XCTAssertNotEqual(revealingContent, settledContent)

        // Leaving and returning once the summary is settled must leave it untouched. A replay
        // would be about a fifth of the way through the six-second reveal at this point.
        host.rootView = content(pushedPath: ["weekly-recap"])
        try await Task.sleep(for: .milliseconds(900))
        host.rootView = content(pushedPath: [])
        try await Task.sleep(for: .milliseconds(1_300))

        let contentAfterReturning = try XCTUnwrap(captureSummaryContent())

        for (name, data) in [
            ("revealing", revealingContent), ("settled", settledContent),
            ("after-returning", contentAfterReturning),
        ] {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = "summary-reappearance-\(name).png"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        window.isHidden = true

        XCTAssertEqual(contentAfterReturning, settledContent)
        // Re-presenting the screen must not ask for the summary again either.
        XCTAssertEqual(requests.deviceIPs, [deviceIP])
        XCTAssertEqual(controller.summary?.content, summaryContent)
        if case .connected = dashboardContext.viewModel.connectionState {
            // Keep the already-loaded Stats visible after leaving and returning too.
        } else {
            XCTFail("Re-presenting the detail screen restarted or lost the existing connection")
        }
    }
}
