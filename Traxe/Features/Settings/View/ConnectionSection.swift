import SwiftUI

struct ConnectionSection: View {
    @Binding var ipAddress: String
    var onSubmit: () -> Void
    var isConnected: Bool

    var body: some View {
        Section("Miner Connection") {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: isConnected)
                    Text("Miner IP")
                }
                Spacer()
                TextField("e.g., 192.168.1.100", text: $ipAddress)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .onSubmit(onSubmit)
                    .textContentType(.URL)
            }
        }
    }
}

#Preview {
    ConnectionSection(ipAddress: .constant("1.1.1.1"), onSubmit: {}, isConnected: true)
}
