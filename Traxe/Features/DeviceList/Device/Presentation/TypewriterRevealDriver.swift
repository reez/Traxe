import Foundation

/// The haptic beats a typewriter reveal asks for as it runs.
enum TypewriterRevealHaptic {
    case step
    case completion
}

/// Drives the timing of the AI summary's typewriter reveal.
///
/// The reveal lives here rather than inside the view so its cancellation contract can be
/// exercised directly: Swift cancellation is cooperative, so every suspension is followed by
/// a cancellation check before the next progress update or haptic. Once the driver is
/// canceled it performs no further work of any kind.
struct TypewriterRevealDriver {
    let characterCount: Int
    var secondsPerCharacter: Double = 0.05
    var maximumStepCount: Int = 100  // Max 100 steps for performance
    var hapticProgressInterval: Double = 0.1

    var stepCount: Int {
        max(1, min(characterCount, maximumStepCount))
    }

    var stepDuration: Double {
        (Double(characterCount) * secondsPerCharacter) / Double(stepCount)
    }

    /// Reports each reveal step and haptic beat in order, returning at the first cancellation
    /// point without reporting anything else.
    ///
    /// - Parameters:
    ///   - showProgress: Receives the reveal progress and the duration to animate it over.
    ///   - playHaptic: Receives each haptic beat, including the final completion beat.
    ///   - sleep: Waits between steps. Injected so tests can hold a step open and resume it.
    func run(
        showProgress: (Double, Double) -> Void,
        playHaptic: (TypewriterRevealHaptic) -> Void,
        sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async {
        let stepCount = self.stepCount
        let stepDuration = self.stepDuration
        var lastHapticProgress = 0.0

        for step in 0...stepCount {
            if Task.isCancelled { return }

            let progress = Double(step) / Double(stepCount)
            showProgress(progress, stepDuration)

            // Play haptic every 10% progress
            if progress - lastHapticProgress >= hapticProgressInterval {
                lastHapticProgress = progress
                playHaptic(.step)
            }

            do {
                try await sleep(.seconds(stepDuration))
            } catch {
                return
            }
        }

        if Task.isCancelled { return }

        // Final completion haptic
        playHaptic(.completion)
    }
}
