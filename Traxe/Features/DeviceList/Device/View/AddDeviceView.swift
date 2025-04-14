import SwiftUI

struct AddDeviceView: View {
    @Environment(\.dismiss) var dismiss

    @State private var ipAddress: String = ""
    @State private var isSaving: Bool = false
    @State private var showingErrorAlert = false
    @State private var errorMessage: String = ""

    private let ipRegex =
        #"^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"#

    var body: some View {
        NavigationView {
            Form {
                Section("Device Details") {
                    HStack {
                        Image(systemName: "network")
                            .foregroundColor(.secondary)
                        TextField("IP Address", text: $ipAddress)
                            .keyboardType(.decimalPad)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                }
            }
            .navigationTitle("Add New Device")
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
                            .disabled(ipAddress.isEmpty || !isValidIP(ipAddress))
                    }
                }
            }
            .alert("Error Adding Device", isPresented: $showingErrorAlert) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func isValidIP(_ ip: String) -> Bool {
        ip.range(of: ipRegex, options: .regularExpression) != nil
    }

    private func addDevice() {
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
}

#Preview {
    AddDeviceView()
}
