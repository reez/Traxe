import SwiftUI

struct WeeklyRecapLastBlockRevealView: View {
    static let revealAnimation = Animation.easeOut(duration: 0.24)
    private static let blockNumberAnimation = Animation.spring(duration: 0.28, bounce: 0.38)
    private static let blockNumberSettleAnimation = Animation.spring(duration: 0.22, bounce: 0.14)

    let lastBlockHeight: Int
    @State private var labelRevealProgress: CGFloat = 0.01
    @State private var isBlockNumberVisible = false
    @State private var blockNumberScale: CGFloat = 0.84
    @State private var blockNumberOffset: CGFloat = 8
    @State private var blockNumberOpacity = 0.0

    private var formattedBlockHeight: String {
        WeeklyRecapChartPresenter.formattedBlockHeight(lastBlockHeight)
    }

    var body: some View {
        HStack(spacing: 3) {
            Text("Last Block")
                .modifier(
                    WeeklyRecapLeadingRevealModifier(progress: labelRevealProgress)
                )

            if isBlockNumberVisible {
                Text(formattedBlockHeight)
                    .fontWeight(.semibold)
                    .contentTransition(.numericText())
                    .scaleEffect(blockNumberScale, anchor: .leading)
                    .offset(x: blockNumberOffset)
                    .opacity(blockNumberOpacity)
            }
        }
        .font(.caption2.weight(.medium))
        .monospacedDigit()
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last block \(formattedBlockHeight)")
        .task {
            guard labelRevealProgress < 1 || !isBlockNumberVisible else { return }

            withAnimation(Self.revealAnimation) {
                labelRevealProgress = 1
            }

            try? await Task.sleep(for: .milliseconds(110))
            isBlockNumberVisible = true

            withAnimation(Self.blockNumberAnimation) {
                blockNumberScale = 1.12
                blockNumberOffset = 0
                blockNumberOpacity = 1
            }

            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(Self.blockNumberSettleAnimation) {
                blockNumberScale = 1
            }
        }
    }
}

private struct WeeklyRecapLeadingRevealModifier: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) {
                Rectangle()
                    .scaleEffect(x: max(progress, 0.001), y: 1, anchor: .leading)
            }
    }
}

#Preview("Weekly Recap - Last Block Reveal") {
    @Previewable @State var lastBlockHeight: Int? = nil

    VStack(alignment: .leading, spacing: 18) {
        WeeklyRecapAllocationRowView(
            labelText: "mine.ocean.xyz",
            logoName: "ocean",
            estimatedHashrate: 20_600,
            lastBlockHeight: lastBlockHeight
        )

        Button("Replay Reveal") {
            lastBlockHeight = nil

            Task {
                try? await Task.sleep(for: .milliseconds(650))
                withAnimation(WeeklyRecapLastBlockRevealView.revealAnimation) {
                    lastBlockHeight = 941_416
                }
            }
        }
        .buttonStyle(.borderedProminent)
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
        LinearGradient(
            colors: [
                Color(.tertiarySystemBackground),
                Color(.secondarySystemBackground),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
    .task {
        guard lastBlockHeight == nil else { return }

        try? await Task.sleep(for: .milliseconds(650))
        withAnimation(WeeklyRecapLastBlockRevealView.revealAnimation) {
            lastBlockHeight = 941_416
        }
    }
}
