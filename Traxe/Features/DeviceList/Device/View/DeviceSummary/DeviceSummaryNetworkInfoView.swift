import Foundation
import SwiftUI

struct DeviceSummaryNetworkInfoView: View {
    let blockHeight: Int?
    let networkDifficulty: Double?

    private var formattedBlockHeight: String? {
        guard let blockHeight else { return nil }
        let currentBlockHeight = max(blockHeight - 1, 0)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: currentBlockHeight))
            ?? "\(currentBlockHeight)"
    }

    private var formattedNetworkDifficulty: (value: String, unit: String)? {
        guard let networkDifficulty else { return nil }
        return networkDifficulty.formattedWithSuffix()
    }

    private var footerText: String? {
        switch (formattedBlockHeight, formattedNetworkDifficulty) {
        case (nil, nil):
            return nil
        case let (blockHeight?, nil):
            return "Block \(blockHeight)"
        case let (nil, difficulty?):
            return "Difficulty \(difficulty.value) \(difficulty.unit)"
        case let (blockHeight?, difficulty?):
            return "Block \(blockHeight) • Difficulty \(difficulty.value) \(difficulty.unit)"
        }
    }

    var body: some View {
        Group {
            if let footerText {
                Text(footerText)
                    .contentTransition(.numericText())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
