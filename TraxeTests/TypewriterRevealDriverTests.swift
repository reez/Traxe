import Foundation
import XCTest

@testable import Traxe

@MainActor
final class TypewriterRevealDriverTests: XCTestCase {

    func testTimingMatchesTheHistoricalTypewriterCadence() {
        let shortSummary = TypewriterRevealDriver(characterCount: 20)
        XCTAssertEqual(shortSummary.stepCount, 20)
        XCTAssertEqual(shortSummary.stepDuration, 0.05, accuracy: 0.000_001)
        XCTAssertEqual(
            shortSummary.stepDuration * Double(shortSummary.stepCount),
            1.0,
            accuracy: 0.000_001
        )

        // The original implementation capped long summaries at 100 animation updates while
        // preserving the same total duration of 50 ms per character.
        let longSummary = TypewriterRevealDriver(characterCount: 250)
        XCTAssertEqual(longSummary.stepCount, 100)
        XCTAssertEqual(longSummary.stepDuration, 0.125, accuracy: 0.000_001)
        XCTAssertEqual(
            longSummary.stepDuration * Double(longSummary.stepCount),
            12.5,
            accuracy: 0.000_001
        )
    }

    func testARunThatIsNotCanceledReportsEveryStepAndEndsWithACompletionHaptic() async {
        var reportedProgress: [Double] = []
        var haptics: [TypewriterRevealHaptic] = []
        var stepHapticProgress: [Double] = []

        let driver = TypewriterRevealDriver(characterCount: 20)
        await driver.run(
            showProgress: { progress, _ in reportedProgress.append(progress) },
            playHaptic: { haptic in
                haptics.append(haptic)
                if haptic == .step, let progress = reportedProgress.last {
                    stepHapticProgress.append(progress)
                }
            },
            sleep: { _ in }
        )

        XCTAssertEqual(reportedProgress.first, 0.0)
        XCTAssertEqual(reportedProgress.last, 1.0)
        XCTAssertEqual(reportedProgress.count, driver.stepCount + 1)
        XCTAssertEqual(reportedProgress, reportedProgress.sorted())
        XCTAssertEqual(haptics.last, .completion)
        XCTAssertEqual(haptics.filter { $0 == .completion }.count, 1)

        // Step haptics mark off roughly every tenth of the reveal. Comparing accumulated
        // fractions never lands exactly on the interval, so a step is occasionally skipped;
        // what matters is that they stay spaced and cover the whole reveal.
        XCTAssertGreaterThanOrEqual(stepHapticProgress.count, 8)
        XCTAssertLessThanOrEqual(stepHapticProgress.count, 10)
        XCTAssertGreaterThan(try XCTUnwrap(stepHapticProgress.first), 0.0)
        for (earlier, later) in zip(stepHapticProgress, stepHapticProgress.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later - earlier, driver.hapticProgressInterval)
        }
    }

    func testCancellingWhileASleepIsSuspendedStopsAllFurtherProgressAndHapticWork() async {
        /// Holds one reveal step open until the test releases it, so cancellation can be
        /// delivered at a known point rather than raced against a wall-clock sleep.
        final class SuspendedStep: @unchecked Sendable {
            private let lock = NSLock()
            private var continuation: CheckedContinuation<Void, Never>?
            private var isSuspended = false
            private var isReleased = false

            var hasSuspended: Bool {
                lock.lock()
                defer { lock.unlock() }
                return isSuspended
            }

            func suspend() async {
                await withCheckedContinuation { newContinuation in
                    lock.lock()
                    isSuspended = true
                    if isReleased {
                        lock.unlock()
                        newContinuation.resume()
                        return
                    }
                    continuation = newContinuation
                    lock.unlock()
                }
            }

            func release() {
                lock.lock()
                isReleased = true
                let pending = continuation
                continuation = nil
                lock.unlock()
                pending?.resume()
            }
        }

        final class Recorder: @unchecked Sendable {
            private let lock = NSLock()
            private var progressStorage: [Double] = []
            private var hapticStorage: [TypewriterRevealHaptic] = []

            var progress: [Double] {
                lock.lock()
                defer { lock.unlock() }
                return progressStorage
            }

            var haptics: [TypewriterRevealHaptic] {
                lock.lock()
                defer { lock.unlock() }
                return hapticStorage
            }

            func recordProgress(_ value: Double) {
                lock.lock()
                progressStorage.append(value)
                lock.unlock()
            }

            func recordHaptic(_ haptic: TypewriterRevealHaptic) {
                lock.lock()
                hapticStorage.append(haptic)
                lock.unlock()
            }
        }

        let suspendedStep = SuspendedStep()
        let recorder = Recorder()
        let reveal = Task {
            // The sleep never completes on its own, so the driver is parked inside a step
            // with plenty of steps still to report.
            await TypewriterRevealDriver(characterCount: 40).run(
                showProgress: { progress, _ in recorder.recordProgress(progress) },
                playHaptic: { recorder.recordHaptic($0) },
                sleep: { _ in await suspendedStep.suspend() }
            )
        }

        while !suspendedStep.hasSuspended {
            await Task.yield()
        }
        let progressBeforeCancellation = recorder.progress

        // Cancel the way SwiftUI does when the view disappears, then let the suspended step
        // finish so the driver resumes after it was already canceled.
        reveal.cancel()
        suspendedStep.release()
        await reveal.value
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(recorder.progress, progressBeforeCancellation)
        XCTAssertLessThan(try XCTUnwrap(recorder.progress.last), 1.0)
        XCTAssertFalse(recorder.haptics.contains(.completion))
    }

    func testAnAlreadyCanceledRunReportsNothingAtAll() async {
        final class Recorder: @unchecked Sendable {
            private let lock = NSLock()
            private var callStorage = 0

            var callCount: Int {
                lock.lock()
                defer { lock.unlock() }
                return callStorage
            }

            func record() {
                lock.lock()
                callStorage += 1
                lock.unlock()
            }
        }

        let recorder = Recorder()
        let reveal = Task {
            // Yielding first guarantees the cancellation below lands before the driver runs.
            await Task.yield()
            await TypewriterRevealDriver(characterCount: 40).run(
                showProgress: { _, _ in recorder.record() },
                playHaptic: { _ in recorder.record() },
                sleep: { _ in }
            )
        }
        reveal.cancel()
        await reveal.value

        XCTAssertEqual(recorder.callCount, 0)
    }
}
