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
            while true {
                try? await Task.sleep(for: .milliseconds(450))
                phase = (phase + 1) % 3
            }
        }
    }
}
