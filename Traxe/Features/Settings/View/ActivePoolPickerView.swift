import SwiftUI

// ESP-Miner v2.15 `useFallbackStratum`: "Fallback" keeps the miner on the fallback pool and
// turns off the automatic switch back to the primary pool. The miner applies it while booting.
struct ActivePoolPickerView: View {
    @Binding var useFallbackStratum: Bool
    let hasFallbackPool: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ACTIVE POOL")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("Active Pool", selection: $useFallbackStratum) {
                Text("Primary").tag(false)
                Text("Fallback").tag(true)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            // Switching back to Primary stays possible even if the fallback pool was cleared.
            .disabled(!hasFallbackPool && !useFallbackStratum)
            Text(
                hasFallbackPool
                    ? "Fallback keeps mining on the fallback pool and does not switch back to the primary pool automatically. Changing this restarts the miner."
                    : "Add a fallback pool to select it."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview("Fallback available") {
    @Previewable @State var useFallbackStratum = true
    Form {
        ActivePoolPickerView(useFallbackStratum: $useFallbackStratum, hasFallbackPool: true)
    }
}

#Preview("No fallback pool") {
    @Previewable @State var useFallbackStratum = false
    Form {
        ActivePoolPickerView(useFallbackStratum: $useFallbackStratum, hasFallbackPool: false)
    }
}
