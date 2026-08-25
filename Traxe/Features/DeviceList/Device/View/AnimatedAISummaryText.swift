import CoreHaptics
import SwiftUI

@available(iOS 18.0, *)
struct TypewriterRenderer: TextRenderer {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        // Count total characters (glyphs)
        let totalGlyphs = layout.flatMap { $0 }.flatMap { $0 }.count
        let glyphsToShow = Int(Double(totalGlyphs) * progress)
        var currentGlyph = 0

        for line in layout {
            for run in line {
                for glyph in run {
                    if currentGlyph < glyphsToShow {
                        context.draw(glyph, options: .disablesSubpixelQuantization)
                    }
                    currentGlyph += 1
                }
            }
        }
    }
}

@available(iOS 18.0, *)
struct AnimatedAISummaryText: View {
    private struct RevealTaskID: Equatable {
        let content: String
        let isDataLoaded: Bool
    }

    let content: String
    let isDataLoaded: Bool
    @State private var progress: Double = 0.0
    @State private var hapticEngine: CHHapticEngine?
    /// The summary value this view has already typed out. `task(id:)` also runs again when
    /// the view reappears, so without this the same summary would reset to zero and replay.
    @State private var revealedContent: String?

    var body: some View {
        let highlighted = content.highlightingValues(color: .traxeGold)
        Text(highlighted)
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .textRenderer(TypewriterRenderer(progress: progress))
            .task {
                await prepareHaptics()
            }
            // One reveal per summary value. SwiftUI cancels the previous reveal before it
            // starts the next one and tears it down on disappear, so a stale reveal can no
            // longer overlap the current one or restart it from zero.
            .task(id: RevealTaskID(content: content, isDataLoaded: isDataLoaded)) {
                await revealContent()
            }
    }

    private func revealContent() async {
        guard !content.isEmpty else { return }

        // A summary can finish generating before the dashboard's first telemetry fetch.
        // Keep it hidden until the data is ready so that the readiness change starts the
        // original typewriter reveal instead of flashing the complete string on screen.
        guard isDataLoaded else { return }

        // This summary has already been typed out during this view's lifetime, so returning
        // to the screen shows it finished instead of replaying the reveal and its haptics.
        // A reveal that was interrupted counts as done and is completed rather than restarted.
        guard revealedContent != content else {
            progress = 1.0
            return
        }
        revealedContent = content
        progress = 0.0

        await TypewriterRevealDriver(characterCount: content.count).run(
            showProgress: { revealProgress, stepDuration in
                withAnimation(.linear(duration: stepDuration)) {
                    progress = revealProgress
                }
            },
            playHaptic: { haptic in
                switch haptic {
                case .step:
                    playTransientHaptic(intensity: 0.3, sharpness: 0.2)
                case .completion:
                    playTransientHaptic(intensity: 0.5, sharpness: 0.8)
                }
            }
        )
    }

    private func prepareHaptics() async {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            let engine = try CHHapticEngine()
            try await engine.start()
            // Starting the engine suspends, so the view may already be gone by the time it
            // finishes; dropping the engine here keeps canceled work out of view state.
            guard !Task.isCancelled else { return }
            hapticEngine = engine
        } catch {
        }
    }

    private func playTransientHaptic(intensity: Float, sharpness: Float) {
        guard let hapticEngine else { return }

        let intensityParameter = CHHapticEventParameter(
            parameterID: .hapticIntensity,
            value: intensity
        )
        let sharpnessParameter = CHHapticEventParameter(
            parameterID: .hapticSharpness,
            value: sharpness
        )

        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [intensityParameter, sharpnessParameter],
            relativeTime: 0
        )

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try hapticEngine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
        }
    }
}

// Fallback for iOS < 18
struct FallbackAISummaryText: View {
    let content: String

    var body: some View {
        let highlighted = content.highlightingValues(color: .traxeGold)
        Text(highlighted)
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: content)
    }
}

#Preview("AI Summary Text") {
    VStack(alignment: .leading, spacing: 20) {
        if #available(iOS 18.0, *) {
            AnimatedAISummaryText(
                content: PreviewFixtures.sampleAISummary.content,
                isDataLoaded: true
            )
        }

        FallbackAISummaryText(content: PreviewFixtures.sampleAISummary.content)
    }
    .padding()
}
