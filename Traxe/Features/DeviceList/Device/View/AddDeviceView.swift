import SwiftUI

struct AddDeviceView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = OnboardingViewModel()

    @State private var ipAddress: String = ""
    @State private var isSaving: Bool = false
    @State private var showingErrorAlert = false
    @State private var errorMessage: String = ""
    @State private var showSettingsAlert = false
    @State private var selectedDevice: DiscoveredDevice?

    private let ipRegex =
        #"^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"#

    private var canAddDevice: Bool {
        selectedDevice != nil || (isValidIP(ipAddress) && !ipAddress.isEmpty)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.tertiarySystemBackground),
                    Color(.secondarySystemBackground),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            NavigationView {
                ScrollView {
                    VStack(spacing: 20) {

                        manualEntrySection()
                            .padding(.top, 8)

                        HStack {
                            VStack { Divider() }
                            Text("Or".uppercased())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .font(.caption)
                            VStack { Divider() }
                        }
                        .padding(.vertical, 8)

                        scanSection()

                        if !viewModel.discoveredDevices.isEmpty {
                            discoveredDevicesSection()
                        }
                    }
                    .padding()
                }
                .onTapGesture {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                }
                .navigationTitle("Add Miner")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Button("Add", action: addDevice)
                                .disabled(!canAddDevice)
                        }
                    }
                }
                .alert("Error Adding Miner", isPresented: $showingErrorAlert) {
                    Button("OK") {}
                } message: {
                    Text(errorMessage)
                }
                .alert("Scan Error", isPresented: $viewModel.showErrorAlert) {
                    Button("OK") {}
                } message: {
                    Text(viewModel.errorMessage)
                }
                .alert("Local Network Access Required", isPresented: $showSettingsAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } message: {
                    Text(
                        "Traxe needs access to your local network to find miners. Please enable it in Settings."
                    )
                }
            }
        }
    }

    private func isValidIP(_ ip: String) -> Bool {
        ip.range(of: ipRegex, options: .regularExpression) != nil
    }

    @ViewBuilder
    private func scanSection() -> some View {
        VStack(spacing: 12) {
            Text(viewModel.scanStatus)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if viewModel.isScanning {
                ProgressView()
            } else {

                if #available(iOS 26.0, *) {
                    Button("Scan Network") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                        Task {
                            let result = await viewModel.startScan()
                            if result == .permissionDenied {
                                self.showSettingsAlert = true
                            }
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.traxeGold)
                    .disabled(viewModel.isScanning)

                } else {
                    Button("Scan Network") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                        Task {
                            let result = await viewModel.startScan()
                            if result == .permissionDenied {
                                self.showSettingsAlert = true
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.traxeGold)
                    .disabled(viewModel.isScanning)

                }

            }
        }
    }

    @ViewBuilder
    private func discoveredDevicesSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 8) {
                ForEach(viewModel.discoveredDevices) { device in
                    deviceRow(device)
                }
            }
        }
    }

    private func deviceRow(_ device: DiscoveredDevice) -> some View {
        Button(action: {
            selectedDevice = device
            ipAddress = ""
        }) {
            VStack(alignment: .leading) {
                HStack {
                    Text(device.name)
                        .font(.headline)
                    Spacer()
                    if selectedDevice?.id == device.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.traxeGold)
                    }
                }
                HStack {
                    Text(device.ip)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(
                        "\(device.hashrate.formatted(.number.precision(.fractionLength(1)))) GH/s"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    Text(
                        "\(device.temperature.formatted(.number.precision(.fractionLength(1))))°C"
                    )
                    .font(.subheadline)
                    .foregroundStyle(device.temperature > 80 ? .red : .blue)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        selectedDevice?.id == device.id ? Color.traxeGold : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.horizontal)
    }

    @ViewBuilder
    private func manualEntrySection() -> some View {
        VStack(spacing: 12) {
            if viewModel.hasScanned && viewModel.discoveredDevices.isEmpty {
                Text("No miners found")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .padding(.bottom, 8)

            HStack {
                Image(systemName: "network")
                    .foregroundStyle(.secondary)
                TextField("IP Address", text: $ipAddress)
                    .textFieldStyle(.plain)
                    .keyboardType(.decimalPad)
                    .autocapitalization(.none)
                    .onChange(of: ipAddress) {
                        if !ipAddress.isEmpty {
                            selectedDevice = nil
                        }
                    }
            }
            .padding()
            .background(Color(uiColor: .systemGray6))
            .clipShape(.rect(cornerRadius: 10))
        }
    }

    private func addSelectedDevice() {
        guard let device = selectedDevice else { return }

        isSaving = true
        viewModel.selectDevice(device)

        Task {
            try? await Task.sleep(for: .milliseconds(200))
            await MainActor.run {
                isSaving = false
                dismiss()
            }
        }
    }

    private func addManualDevice() {
        guard isValidIP(ipAddress) else {
            errorMessage = "Please enter a valid IP address."
            showingErrorAlert = true
            return
        }

        isSaving = true
        let trimmedIP = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                let discoveredDevice = try await DeviceManagementService.checkDevice(ip: trimmedIP)
                let deviceToSave = SavedDevice(
                    name: discoveredDevice.name,
                    ipAddress: discoveredDevice.ip
                )
                try DeviceManagementService.saveDevice(deviceToSave)

                await MainActor.run {
                    isSaving = false
                    dismiss()
                }

            } catch let error as DeviceCheckError {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingErrorAlert = true
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    errorMessage =
                        "An unexpected error occurred while saving: \(error.localizedDescription)"
                    showingErrorAlert = true
                    isSaving = false
                }
            }
        }
    }

    private func addDevice() {
        if selectedDevice != nil {
            addSelectedDevice()
        } else if isValidIP(ipAddress) && !ipAddress.isEmpty {
            addManualDevice()
        }
    }
}

#Preview {
    AddDeviceView()
}
