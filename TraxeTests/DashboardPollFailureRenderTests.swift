import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import Traxe

/// Visual QA for the miner summary's Stats grid after a single failed poll. The grid is rendered
/// from a live `DashboardViewModel` right after it connected and again once one poll has failed,
/// so the images show what the screen does rather than a forced state. Off by default so
/// ordinary test runs stay fast.
@MainActor
final class DashboardPollFailureRenderTests: XCTestCase {
    func testRenderSummaryGridAfterOneFailedPoll() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            environment["RENDER_DASHBOARD_POLL_FAILURE"] == "1"
                || environment["TEST_RUNNER_RENDER_DASHBOARD_POLL_FAILURE"] == "1"
        else {
            throw XCTSkip("Set RENDER_DASHBOARD_POLL_FAILURE=1 to render visual QA states.")
        }

        // Keeps the rendered app code on its preview path: no RevenueCat, no networking.
        setenv("XCODE_RUNNING_FOR_PREVIEWS", "1", 1)
        UIView.setAnimationsEnabled(false)
        addTeardownBlock {
            unsetenv("XCODE_RUNNING_FOR_PREVIEWS")
            UIView.setAnimationsEnabled(true)
        }

        let outputDirectory = URL(
            fileURLWithPath: environment["DASHBOARD_POLL_FAILURE_DIR"]
                ?? environment["TEST_RUNNER_DASHBOARD_POLL_FAILURE_DIR"]
                ?? "screenshots/visual-qa/dashboard-poll-failure"
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent("esp-miner-2-15-0-system-info.json")
        let telemetry = try JSONDecoder().decode(
            MinerTelemetryDTO.self,
            from: Data(contentsOf: fixtureURL)
        )

        actor FetchSequence {
            private var count = 0
            private var secondFetchContinuation: CheckedContinuation<Void, Never>?
            private var isSecondFetchReleased = false
            func next() -> Int {
                count += 1
                return count
            }
            func holdSecondFetch() async {
                guard !isSecondFetchReleased else { return }
                await withCheckedContinuation { secondFetchContinuation = $0 }
            }
            func releaseSecondFetch() {
                isSecondFetchReleased = true
                secondFetchContinuation?.resume()
                secondFetchContinuation = nil
            }
        }
        let sequence = FetchSequence()
        let thirdFetchStarted = expectation(description: "The third fetch started")
        let schema = Schema([HistoricalDataPoint.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let viewModel = DashboardViewModel(
            modelContext: container.mainContext,
            dependencies: .init(
                network: .init(fetchMinerTelemetry: { _ in
                    // 1: connect. 2: one dropped request, held until the connected state has
                    // been rendered. 3 and later: never answer, so the state after the single
                    // failure holds still while it is rendered.
                    switch await sequence.next() {
                    case 1:
                        return telemetry
                    case 2:
                        await sequence.holdSecondFetch()
                        throw URLError(.timedOut)
                    case 3:
                        thirdFetchStarted.fulfill()
                        try await Task.sleep(for: .seconds(3_600))
                        throw URLError(.timedOut)
                    default:
                        try await Task.sleep(for: .seconds(3_600))
                        throw URLError(.timedOut)
                    }
                }),
                selectedDeviceID: { "192.168.1.100" },
                notificationCenter: NotificationCenter(),
                makeNetworkMonitor: nil,
                networkMonitorQueue: .main,
                sleep: { duration in try? await Task.sleep(for: duration) },
                pollingInterval: .milliseconds(50)
            )
        )

        let size = CGSize(width: 393, height: 852)
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        // The Stats section as the miner summary lays it out, with the real grid.
        let host = UIHostingController(
            rootView: ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Stats")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.horizontal)
                    MetricsSummaryGrid(viewModel: viewModel)
                }
                .padding(.vertical)
            }
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds

        let states = ["01-connected.png", "02-after-one-failed-poll.png"]
        for (index, filename) in states.enumerated() {
            if index == 0 {
                await viewModel.connect()
                XCTAssertEqual(viewModel.connectionState, .connected)
            } else {
                // Let the held second fetch fail. The third fetch only starts after that
                // failure was handled.
                await sequence.releaseSecondFetch()
                await fulfillment(of: [thirdFetchStarted], timeout: 5)
            }
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            host.view.layoutIfNeeded()

            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            format.opaque = true
            let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let pngData = try XCTUnwrap(rendered.pngData())
            try pngData.write(to: outputDirectory.appendingPathComponent(filename))
        }
        viewModel.disconnect()
        window.isHidden = true
    }
}
