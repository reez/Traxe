import SwiftUI

struct AddDeviceDiscoveredDeviceRow: View {
    let name: String
    let ip: String
    let hashrate: Double
    let temperature: Double
    let isSelected: Bool
    let isAlreadySaved: Bool
    let isSelectionDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading) {
                HStack {
                    Text(name)
                        .font(.headline)

                    Spacer()

                    selectionStatus
                }

                HStack {
                    Text(ip)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(hashrate.formatted(.number.precision(.fractionLength(1)))) GH/s")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("\(temperature.formatted(.number.precision(.fractionLength(1))))°C")
                        .font(.subheadline)
                        .foregroundStyle(temperature > 80 ? .red : .blue)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.traxeGold : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isAlreadySaved || isSelectionDisabled)
        .opacity(isAlreadySaved || isSelectionDisabled ? 0.65 : 1)
    }

    @ViewBuilder
    private var selectionStatus: some View {
        if isAlreadySaved {
            Label("Added", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    VStack {
        AddDeviceDiscoveredDeviceRow(
            name: "bitaxe-601",
            ip: "192.168.1.55",
            hashrate: 650.2,
            temperature: 62.4,
            isSelected: true,
            isAlreadySaved: false,
            isSelectionDisabled: false,
            action: {}
        )

        AddDeviceDiscoveredDeviceRow(
            name: "bitaxe-602",
            ip: "192.168.1.56",
            hashrate: 640.8,
            temperature: 64.1,
            isSelected: false,
            isAlreadySaved: true,
            isSelectionDisabled: false,
            action: {}
        )
    }
    .padding()
}
