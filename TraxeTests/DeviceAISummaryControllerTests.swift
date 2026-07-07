import Foundation
import XCTest

@testable import Traxe

@MainActor
final class DeviceAISummaryControllerTests: XCTestCase {

    func testRepeatedLifecycleTriggersForOneMinerRunASingleGenerationAndPublishOneSummary()
        async throws
    {
        final class RequestLog: @unchecked Sendable {
            private let lock = NSLock()
            private var storage: [String] = []

            var deviceIPs: [String] {
                lock.lock()
                defer { lock.unlock() }
                return storage
            }

            func record(_ deviceIP: String) -> Int {
                lock.lock()
                defer { lock.unlock() }
                storage.append(deviceIP)
                return storage.count
            }
        }

        let requests = RequestLog()
        let controller = DeviceAISummaryController(
            dependencies: .init(startDelay: .zero) { deviceIP, _ in
                let requestNumber = requests.record(deviceIP)
                try await Task.sleep(for: .milliseconds(30))
                return AISummary(content: "Summary \(requestNumber)")
            }
        )

        // Three overlapping appearances, the shape of the repeated lifecycle events the
        // split view produces while it pushes and settles the detail column.
        async let firstAppearance: Void = controller.loadSummary(
            for: "192.168.1.50",
            historicalData: []
        )
        async let secondAppearance: Void = controller.loadSummary(
            for: "192.168.1.50",
            historicalData: []
        )
        async let thirdAppearance: Void = controller.loadSummary(
            for: "192.168.1.50",
            historicalData: []
        )
        _ = await (firstAppearance, secondAppearance, thirdAppearance)

        // A later appearance, once the summary is already on screen, must not regenerate it.
        await controller.loadSummary(for: "192.168.1.50", historicalData: [])

        XCTAssertEqual(requests.deviceIPs, ["192.168.1.50"])
        XCTAssertEqual(controller.summary?.content, "Summary 1")
        XCTAssertFalse(controller.isGenerating)
    }

    func testSwitchingMinersDiscardsTheSummaryGeneratedForThePreviousMiner() async throws {
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

        let previousMinerIP = "192.168.1.60"
        let selectedMinerIP = "192.168.1.61"
        let requests = RequestLog()
        let controller = DeviceAISummaryController(
            dependencies: .init(startDelay: .zero) { deviceIP, _ in
                requests.record(deviceIP)
                // The miner that is navigated away from answers late, so its result would
                // otherwise land on the screen after the selection already changed.
                try await Task.sleep(
                    for: .milliseconds(deviceIP == previousMinerIP ? 200 : 10)
                )
                return AISummary(content: "Summary for \(deviceIP)")
            }
        )

        let staleAppearance = Task {
            await controller.loadSummary(for: previousMinerIP, historicalData: [])
        }
        try await Task.sleep(for: .milliseconds(20))

        await controller.loadSummary(for: selectedMinerIP, historicalData: [])
        XCTAssertEqual(controller.summary?.content, "Summary for \(selectedMinerIP)")

        // Wait past the point where the previous miner's request would have finished.
        await staleAppearance.value
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(requests.deviceIPs, [previousMinerIP, selectedMinerIP])
        XCTAssertEqual(controller.summary?.content, "Summary for \(selectedMinerIP)")
        XCTAssertFalse(controller.isGenerating)
    }

    func testAStaleMinerResultThatCompletesDespiteCancellationIsRejected() async throws {
        /// Stands in for network or model work that ignores cancellation and returns a value
        /// anyway, so the controller's own guard is what has to reject the stale summary.
        final class UncancellableWork: @unchecked Sendable {
            private let lock = NSLock()
            private var continuation: CheckedContinuation<Void, Never>?
            private var hasStarted = false
            private var isFinished = false

            var didStart: Bool {
                lock.lock()
                defer { lock.unlock() }
                return hasStarted
            }

            func wait() async {
                await withCheckedContinuation { newContinuation in
                    lock.lock()
                    hasStarted = true
                    if isFinished {
                        lock.unlock()
                        newContinuation.resume()
                        return
                    }
                    continuation = newContinuation
                    lock.unlock()
                }
            }

            func finish() {
                lock.lock()
                isFinished = true
                let pending = continuation
                continuation = nil
                lock.unlock()
                pending?.resume()
            }
        }

        let previousMinerIP = "192.168.1.64"
        let selectedMinerIP = "192.168.1.65"
        let staleWork = UncancellableWork()
        let controller = DeviceAISummaryController(
            dependencies: .init(startDelay: .zero) { deviceIP, _ in
                if deviceIP == previousMinerIP {
                    await staleWork.wait()
                }
                return AISummary(content: "Summary for \(deviceIP)")
            }
        )

        let staleAppearance = Task {
            await controller.loadSummary(for: previousMinerIP, historicalData: [])
        }
        while !staleWork.didStart {
            await Task.yield()
        }

        await controller.loadSummary(for: selectedMinerIP, historicalData: [])
        XCTAssertEqual(controller.summary?.content, "Summary for \(selectedMinerIP)")

        // The previous miner's request now completes even though it was canceled.
        staleWork.finish()
        await staleAppearance.value
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(controller.summary?.content, "Summary for \(selectedMinerIP)")
        XCTAssertFalse(controller.isGenerating)
    }

    func testCancellingPendingWorkStopsGeneratingBeforeAnyResultIsProduced() async throws {
        final class GenerationFlag: @unchecked Sendable {
            private let lock = NSLock()
            private var storage = false

            var didRun: Bool {
                lock.lock()
                defer { lock.unlock() }
                return storage
            }

            func markRun() {
                lock.lock()
                storage = true
                lock.unlock()
            }
        }

        let generation = GenerationFlag()
        let controller = DeviceAISummaryController(
            dependencies: .init(startDelay: .milliseconds(500)) { _, _ in
                generation.markRun()
                return AISummary(content: "Should never be published")
            }
        )

        let appearance = Task {
            await controller.loadSummary(for: "192.168.1.70", historicalData: [])
        }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(controller.isGenerating)

        controller.cancelPendingWork()
        await appearance.value
        try await Task.sleep(for: .milliseconds(600))

        XCTAssertFalse(generation.didRun)
        XCTAssertNil(controller.summary)
        XCTAssertFalse(controller.isGenerating)
    }

    func testFailedGenerationLeavesNoSummaryAndStopsGenerating() async throws {
        struct GenerationFailure: Error {}

        let controller = DeviceAISummaryController(
            dependencies: .init(startDelay: .zero) { _, _ in
                throw GenerationFailure()
            }
        )

        await controller.loadSummary(for: "192.168.1.80", historicalData: [])

        XCTAssertNil(controller.summary)
        XCTAssertFalse(controller.isGenerating)
    }
}
