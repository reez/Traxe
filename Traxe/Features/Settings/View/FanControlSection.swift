import Observation
import SwiftUI

struct FanControlSection: View {
    @Bindable var viewModel: SettingsViewModel

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
                    .foregroundStyle(viewModel.isAutoFan ? Color.secondary : Color.primary)
                Spacer()

                Button(action: { Task { await viewModel.adjustFanSpeed(by: -5) } }) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(
                            isControlDisabled || viewModel.fanSpeed <= 0
                                ? Color.secondary
                                : Color.traxeGold
                        )
                }
                .disabled(isControlDisabled || viewModel.fanSpeed <= 0)

                Text("\(viewModel.fanSpeed)%")
                    .foregroundStyle(
                        viewModel.isAutoFan ? Color.secondary : Color.traxeGold
                    )
                    .frame(width: 50)

                Button(action: { Task { await viewModel.adjustFanSpeed(by: 5) } }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(
                            isControlDisabled || viewModel.fanSpeed >= 100
                                ? Color.secondary
                                : Color.traxeGold
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
                    .foregroundStyle(viewModel.isAutoFan ? Color.secondary : Color.clear)
                if let minimumFanSpeed = viewModel.minimumFanSpeed {
                    Text("Auto fan minimum: \(minimumFanSpeed)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
    }
}
