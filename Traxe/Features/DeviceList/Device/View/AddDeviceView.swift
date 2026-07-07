import SwiftUI

struct AddDeviceView: View {
    @Environment(\.dismiss) var dismiss
    @State private var viewModel: OnboardingViewModel

    @State private var ipAddress: String = ""
    @State private var isSaving: Bool = false
    @State private var showingErrorAlert = false
    @State private var errorMessage: String = ""
    @State private var showSettingsAlert = false
    @State private var selectedDeviceIPs: Set<String>
    @FocusState private var isIPAddressFocused: Bool

    private let existingDeviceIPs: Set<String>
    private let deviceLimit: Int

    private let ipRegex =
        #"^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"#

    @MainActor
    init(
        existingDeviceIPs: Set<String> = [],
        deviceLimit: Int = Int.max
    ) {
        self.init(
            existingDeviceIPs: existingDeviceIPs,
            deviceLimit: deviceLimit,
            viewModel: OnboardingViewModel(),
            selectedDeviceIPs: []
        )
    }

    init(
        existingDeviceIPs: Set<String>,
        deviceLimit: Int,
        viewModel: OnboardingViewModel,
        selectedDeviceIPs: Set<String>
    ) {
        self.existingDeviceIPs = existingDeviceIPs
        self.deviceLimit = deviceLimit
        self._viewModel = State(initialValue: viewModel)
        self._selectedDeviceIPs = State(initialValue: selectedDeviceIPs)
    }

    private var remainingDeviceSlots: Int {
        guard deviceLimit != Int.max else { return Int.max }
        return max(deviceLimit - existingDeviceIPs.count, 0)
    }

    private var selectableDiscoveredDevices: [DiscoveredDevice] {
        viewModel.discoveredDevices.filter { !existingDeviceIPs.contains($0.ip) }
    }

    private var limitedSelectableDiscoveredDevices: [DiscoveredDevice] {
        guard remainingDeviceSlots != Int.max else { return selectableDiscoveredDevices }
        return Array(selectableDiscoveredDevices.prefix(remainingDeviceSlots))
    }

    private var selectedDiscoveredDevices: [DiscoveredDevice] {
        viewModel.discoveredDevices.filter {
            selectedDeviceIPs.contains($0.ip) && !existingDeviceIPs.contains($0.ip)
        }
    }

    private var canSelectMoreDiscoveredDevices: Bool {
        remainingDeviceSlots == Int.max || selectedDiscoveredDevices.count < remainingDeviceSlots
    }

    private var canAddDevice: Bool {
        remainingDeviceSlots != 0
            && (!selectedDiscoveredDevices.isEmpty || (isValidIP(ipAddress) && !ipAddress.isEmpty))
    }

    private var selectionStatusText: String? {
        guard remainingDeviceSlots != Int.max, !selectableDiscoveredDevices.isEmpty else {
            return nil
        }

        let selectedCount = selectedDiscoveredDevices.count
        let slotLabel = remainingDeviceSlots == 1 ? "slot" : "slots"
        let baseStatus = "\(selectedCount) of \(remainingDeviceSlots) \(slotLabel) selected"

        if remainingDeviceSlots == 0 || selectedCount == remainingDeviceSlots {
            return "\(baseStatus). No more slots available."
        }

        return baseStatus
    }

    private var areAllSelectableDevicesSelected: Bool {
        !limitedSelectableDiscoveredDevices.isEmpty
            && limitedSelectableDiscoveredDevices.allSatisfy { selectedDeviceIPs.contains($0.ip) }
    }

    private var selectAllButtonTitle: String {
        areAllSelectableDevicesSelected ? "Deselect All" : "Select All"
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

            NavigationStack {
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
                .scrollDismissesKeyboard(.immediately)
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
                    Button("Scan Network", action: startScan)
                        .buttonStyle(.glassProminent)
                        .tint(Color.traxeGold)
                        .disabled(viewModel.isScanning)

                } else {
                    Button("Scan Network", action: startScan)
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
            selectionControls()

            VStack(spacing: 8) {
                ForEach(viewModel.discoveredDevices) { device in
                    deviceRow(device)
                }
            }
        }
    }

    private func selectionControls() -> some View {
        HStack(alignment: .firstTextBaseline) {
            if let selectionStatusText {
                Text(selectionStatusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !selectableDiscoveredDevices.isEmpty {
                Button(selectAllButtonTitle, action: toggleSelectAllDiscoveredDevices)
                    .font(.subheadline)
                    .disabled(remainingDeviceSlots == 0)
            }
        }
        .padding(.horizontal)
    }

    private func deviceRow(_ device: DiscoveredDevice) -> some View {
        let isSelected = selectedDeviceIPs.contains(device.ip)
        let isAlreadySaved = existingDeviceIPs.contains(device.ip)
        let isSelectionDisabled = !isSelected && !canSelectMoreDiscoveredDevices

        return AddDeviceDiscoveredDeviceRow(
            name: device.name,
            ip: device.ip,
            hashrate: device.hashrate,
            temperature: device.temperature,
            isSelected: isSelected,
            isAlreadySaved: isAlreadySaved,
            isSelectionDisabled: isSelectionDisabled,
            action: {
                toggleDiscoveredDeviceSelection(device)
            }
        )
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
                    .textInputAutocapitalization(.never)
                    .focused($isIPAddressFocused)
                    .onChange(of: ipAddress) {
                        if !ipAddress.isEmpty {
                            selectedDeviceIPs.removeAll()
                        }
                    }
            }
            .padding()
            .background(Color(uiColor: .systemGray6))
            .clipShape(.rect(cornerRadius: 10))
        }
    }

    private func startScan() {
        isIPAddressFocused = false
        selectedDeviceIPs.removeAll()
        Task {
            let result = await viewModel.startScan()
            if result == .permissionDenied {
                self.showSettingsAlert = true
            }
        }
    }

    private func toggleDiscoveredDeviceSelection(_ device: DiscoveredDevice) {
        guard !existingDeviceIPs.contains(device.ip) else { return }

        ipAddress = ""

        if selectedDeviceIPs.contains(device.ip) {
            selectedDeviceIPs.remove(device.ip)
        } else if canSelectMoreDiscoveredDevices {
            selectedDeviceIPs.insert(device.ip)
        }
    }

    private func toggleSelectAllDiscoveredDevices() {
        ipAddress = ""
        let selectableIPs = Set(selectableDiscoveredDevices.map(\.ip))

        if areAllSelectableDevicesSelected {
            selectedDeviceIPs.subtract(selectableIPs)
        } else {
            selectedDeviceIPs = Set(limitedSelectableDiscoveredDevices.map(\.ip))
        }
    }

    private func addSelectedDevices() {
        let devices = selectedDiscoveredDevices
        guard !devices.isEmpty else { return }

        isSaving = true
        guard viewModel.selectDevices(devices) else {
            isSaving = false
            return
        }

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
        isIPAddressFocused = false
        if !selectedDiscoveredDevices.isEmpty {
            addSelectedDevices()
        } else if isValidIP(ipAddress) && !ipAddress.isEmpty {
            addManualDevice()
        }
    }
}

#Preview {
    AddDeviceView()
}
