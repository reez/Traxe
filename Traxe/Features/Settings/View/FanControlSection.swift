import SwiftUI

struct FanControlSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    private var isControlDisabled: Bool {
        viewModel.isAutoFan || viewModel.isUpdatingFan
    }

    var body: some View {
        Section {
            Toggle(
                "Auto Fan",
                isOn: Binding(
                    get: { viewModel.isAutoFan },
                    set: { _ in Task { await viewModel.toggleAutoFan() } }
                )
            )
            .disabled(viewModel.isUpdatingFan)
            .tint(.traxeGold)

            HStack {
                Text("Fan Speed")
                    .foregroundColor(viewModel.isAutoFan ? .secondary : .primary)
                Spacer()

                Button(action: { Task { await viewModel.adjustFanSpeed(by: -5) } }) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(
                            isControlDisabled || viewModel.fanSpeed <= 0 ? .secondary : .traxeGold
                        )
                }
                .disabled(isControlDisabled || viewModel.fanSpeed <= 0)

                Text("\(viewModel.fanSpeed)%")
                    .foregroundColor(viewModel.isAutoFan ? .secondary : .traxeGold)
                    .frame(width: 50)

                Button(action: { Task { await viewModel.adjustFanSpeed(by: 5) } }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(
                            isControlDisabled || viewModel.fanSpeed >= 100 ? .secondary : .traxeGold
                        )
                }
                .disabled(isControlDisabled || viewModel.fanSpeed >= 100)
            }
            .disabled(viewModel.isUpdatingFan)
        } header: {
            Text("Fan Control")
        } footer: {
            VStack(alignment: .leading) {
                Text("Switch Auto Fan **Off** to manually control fan speed.")
                    .foregroundColor(viewModel.isAutoFan ? .secondary : .clear)
                if let minimumFanSpeed = viewModel.minimumFanSpeed {
                    Text("Auto fan minimum: \(minimumFanSpeed)%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
        }
    }
}
