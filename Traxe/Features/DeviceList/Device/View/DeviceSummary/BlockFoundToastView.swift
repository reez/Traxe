import Foundation
import SwiftUI

struct BlockFoundToastView: View {
    let blockHeight: Int?
    let poolName: String?

    private var formattedBlockHeight: String? {
        guard let blockHeight else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: blockHeight)) ?? "\(blockHeight)"
    }

    private var messageText: String {
        let poolSuffix = (poolName?.isEmpty == false) ? " by \(poolName ?? "")" : ""
        if let formattedHeight = formattedBlockHeight {
            return "Block \(formattedHeight) found\(poolSuffix)"
        }
        return "Block found\(poolSuffix)"
    }

    var body: some View {
        HStack {
            Text(messageText)
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .toastSurface()
    }
}

extension View {
    /// The toast floats over the scroll view rather than inside it, so it can be
    /// Liquid Glass on iOS 26 without the instability glass shows while scrolling.
    @ViewBuilder
    fileprivate func toastSurface() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: .rect(cornerRadius: 12, style: .continuous))
        } else {
            background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.secondary.opacity(0.3), lineWidth: 0.5)
            )
        }
    }
}

#Preview("Block Found Toast") {
    BlockFoundToastView(
        blockHeight: 941_416,
        poolName: "mine.ocean.xyz"
    )
    .padding()
}
