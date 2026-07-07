import SwiftUI

struct TypingDots: View {
    @State private var phase: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var label: String? = "Generating summary…"

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 6, height: 6)
                        .opacity(phase == i ? 1 : 0.25)
                }
            }
            if let label {
                Text(label)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(label ?? "Loading")
        .task {
            guard !reduceMotion else { return }
            // `Task.sleep` throws as soon as SwiftUI cancels this task, so leaving the
            // loop on that error is what keeps a view that is being removed from
            // spinning through phases instead of holding the 450 ms cadence. Cancellation
            // can also land just as a sleep succeeds, so the phase only advances after a
            // second check.
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(450))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                phase = (phase + 1) % 3
            }
        }
    }
}

#Preview("Typing Dots") {
    TypingDots()
        .padding()
}
