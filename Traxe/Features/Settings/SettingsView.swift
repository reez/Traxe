import SwiftUI

// MARK: - Connection Section
struct ConnectionSection: View {
    @Binding var ipAddress: String
    var onSubmit: () -> Void
    var isConnected: Bool

    var body: some View {
        Section("Device Connection") {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: isConnected)
                    Text("BitAxe IP Address")
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

// MARK: - Firmware Section
struct FirmwareSection: View {
    let currentVersion: String
    let isUpdating: Bool
    let updateError: String?
    let onUpdate: () -> Void

    var body: some View {
        Section {
            HStack {
                Text("Firmware Version")
                Spacer()
                Text(currentVersion)
                    .foregroundColor(.secondary)
            }

            Button(action: onUpdate) {
                HStack {
                    Text("Check for Updates")
                        .foregroundColor(.traxeGold)
                    Spacer()
                    if isUpdating {
                        ProgressView()
                    }
                }
            }
            .disabled(isUpdating)

            if let error = updateError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
            }
        } header: {
            Text("Firmware")
        } footer: {
            Text("I have not tested this yet myself, so extra caution!")
                .font(.caption2)
                .foregroundColor(.red)
        }
    }
}

// MARK: - Danger Zone Section
struct DangerZoneSection: View {
    let onRestart: () -> Void

    var body: some View {
        Section {
            Button("Restart BitAxe Device", role: .destructive, action: onRestart)
        } header: {
            Text("Danger Zone")
        }
    }
}

// MARK: - Fan Control Section
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
                    .foregroundColor(viewModel.isAutoFan ? .gray : .primary)
                Spacer()

                Button(action: { Task { await viewModel.adjustFanSpeed(by: -5) } }) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(
                            isControlDisabled || viewModel.fanSpeed <= 0 ? .gray : .traxeGold
                        )
                }
                .disabled(isControlDisabled || viewModel.fanSpeed <= 0)

                Text("\(viewModel.fanSpeed)%")
                    .foregroundColor(viewModel.isAutoFan ? .gray : .secondary)
                    .frame(width: 50)

                Button(action: { Task { await viewModel.adjustFanSpeed(by: 5) } }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(
                            isControlDisabled || viewModel.fanSpeed >= 100 ? .gray : .traxeGold
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
                Text("I have not tested this yet myself, so extra caution!")
                    .font(.caption2)
                    .foregroundColor(.red)
                    .padding(.top, 2)
            }
        }
    }
}

// MARK: - Main View
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @Environment(\.dismiss) var dismiss
    @State private var showingRestartConfirmation = false

    var body: some View {
        NavigationView {
            Form {
                ConnectionSection(
                    ipAddress: $viewModel.bitaxeIPAddress,
                    onSubmit: viewModel.saveSettings,
                    isConnected: viewModel.isConnected
                )

                Section("Firmware") {
                    HStack {
                        Text("Firmware Version")
                        Spacer()
                        Text(viewModel.currentVersion)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Reset") {
                    Button("Reset Connection & Clear Data", role: .destructive) {
                        viewModel.requestResetConfirmation()
                    }
                }

                Section {
                    NavigationLink("Advanced Settings") {
                        AdvancedSettingsView(viewModel: viewModel)
                    }
                }

            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.saveSettings()
                        dismiss()
                    }
                    .foregroundColor(.traxeGold)
                }
            }
            .alert("Confirm Reset", isPresented: $viewModel.showingResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    viewModel.performReset()
                    dismiss()
                }
            } message: {
                Text(
                    "This will clear the saved IP address, alert settings, and delete all historical data. Are you sure?"
                )
            }
        }
    }
}

struct AdvancedSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showingRestartConfirmation = false

    var body: some View {
        Form {
            FanControlSection(viewModel: viewModel)
                .safeAreaPadding(.bottom, 10)

            FirmwareSection(
                currentVersion: viewModel.currentVersion,
                isUpdating: viewModel.isUpdating,
                updateError: viewModel.updateError,
                onUpdate: viewModel.requestUpdateConfirmation
            )

            DangerZoneSection(onRestart: { showingRestartConfirmation = true })
        }
        .navigationTitle("Advanced Settings")
        .alert("Restart Device", isPresented: $showingRestartConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Restart", role: .destructive) {
                Task { await viewModel.restartDevice() }
            }
        } message: {
            Text(
                "Are you sure you want to restart the device? This will temporarily stop mining operations."
            )
        }
    }
}

// MARK: - Preview Provider

#Preview {
    SettingsView()
}
