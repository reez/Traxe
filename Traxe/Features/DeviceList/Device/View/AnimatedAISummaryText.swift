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
    let content: String
    let isDataLoaded: Bool
    @State private var progress: Double = 0.0
    @State private var hapticEngine: CHHapticEngine?
    @State private var animationTask: Task<Void, Never>?
    @State private var lastHapticProgress: Double = 0.0

    var body: some View {
        let highlighted = content.highlightingValues(color: .traxeGold)
        Text(highlighted)
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .textRenderer(TypewriterRenderer(progress: progress))
            .onAppear {
                startAnimationIfReady()
            }
            .onChange(of: content) { _, newContent in
                animationTask?.cancel()
                progress = 0.0
                lastHapticProgress = 0.0
                startAnimationIfReady()
            }
            .onChange(of: isDataLoaded) { _, loaded in
                if loaded && !content.isEmpty && progress == 0.0 {
                    startAnimationIfReady()
                }
            }
            .onDisappear {
                animationTask?.cancel()
            }
    }

    private func startAnimationIfReady() {
        // Only start animation if data is loaded
        guard isDataLoaded && !content.isEmpty else {
            // Show content immediately if data isn't loaded yet
            progress = 1.0
            return
        }

        startAnimation()
    }

    private func startAnimation() {
        animationTask?.cancel()

        // Prepare haptics on background thread
        Task.detached(priority: .background) {
            await prepareHaptics()
        }

        // Start the character-by-character animation
        animationTask = Task.detached(priority: .userInitiated) {
            let totalCharacters = content.count
            let animationDuration: TimeInterval = Double(totalCharacters) * 0.05  // 50ms per character
            let steps = min(totalCharacters, 100)  // Max 100 steps for performance
            let stepDuration = animationDuration / Double(steps)

            for step in 0...steps {
                let newProgress = Double(step) / Double(steps)

                await MainActor.run {
                    withAnimation(.linear(duration: stepDuration)) {
                        progress = newProgress
                    }
                }

                // Play haptic every 10% progress and only after data is loaded
                let shouldTriggerHaptic = await MainActor.run { () -> Bool in
                    guard isDataLoaded else { return false }
                    let needsHaptic = newProgress - lastHapticProgress >= 0.1
                    if needsHaptic {
                        lastHapticProgress = newProgress
                    }
                    return needsHaptic
                }

                if shouldTriggerHaptic {
                    Task.detached(priority: .background) {
                        await playHaptic()
                    }
                }

                try? await Task.sleep(for: .seconds(stepDuration))
            }

            // Final completion haptic
            if isDataLoaded {
                Task.detached(priority: .background) {
                    await playCompletionHaptic()
                }
            }
        }
    }

    private func prepareHaptics() async {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            let engine = try CHHapticEngine()
            try await engine.start()
            await MainActor.run {
                hapticEngine = engine
            }
        } catch {
        }
    }

    private func playHaptic() async {
        let engine = await MainActor.run { hapticEngine }
        guard let hapticEngine = engine else { return }

        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)

        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [intensity, sharpness],
            relativeTime: 0
        )

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try hapticEngine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
        }
    }

    private func playCompletionHaptic() async {
        let engine = await MainActor.run { hapticEngine }
        guard let hapticEngine = engine else { return }

        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)

        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [intensity, sharpness],
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
