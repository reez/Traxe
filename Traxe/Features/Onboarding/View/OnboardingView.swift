import SwiftData
import SwiftUI

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @State private var navigateToDeviceList = false
    @State private var showSettingsAlert = false
    @State private var showConnectionError = false
    @State private var connectionError = ""
    let dashboardViewModel: DashboardViewModel
    @State private var pulse = false
    @State private var isConnecting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Spacer().frame(height: 20)

                onboardingHeaderAndScanButton()

                if !viewModel.discoveredDevices.isEmpty {
                    List(viewModel.discoveredDevices) { device in
                        deviceRow(device)
                    }
                    .listStyle(.plain)
                    .frame(height: CGFloat(viewModel.discoveredDevices.count) * 80)
                }

                manualEntrySection()

                Spacer()

                HStack(spacing: 4) {
                    Link(
                        "Privacy Policy",
                        destination: URL(string: "https://matthewramsden.com/privacy")!
                    )
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Link(
                        "Terms of Use",
                        destination: URL(
                            string:
                                "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
                        )!
                    )
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            }
            .padding()
            .animation(.easeInOut, value: viewModel.isScanning)
            .navigationTitle("Welcome")
            .navigationBarHidden(true)
            .alert("Scan Error", isPresented: $viewModel.showErrorAlert) {
                Button("OK") {}
            } message: {
                var message = viewModel.errorMessage
                if !viewModel.deviceInfo.isEmpty {
                    message += "\n\n\(viewModel.deviceInfo)"
                }
                if !viewModel.problemField.isEmpty {
                    message += "\n\(viewModel.problemField)"
                }
                return Text(message)
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
                    "Traxe needs access to your local network to find devices. Please enable it in Settings."
                )
            }
            .alert("Connection Error", isPresented: $showConnectionError) {
                Button("OK") {}
            } message: {
                Text(connectionError)
            }
            .navigationDestination(isPresented: $navigateToDeviceList) {
                DeviceListView(
                    dashboardViewModel: dashboardViewModel,
                    navigateToDeviceList: $navigateToDeviceList
                )
            }
        }
    }

    private func deviceRow(_ device: DiscoveredDevice) -> some View {
        Button(action: {
            guard !isConnecting else { return }
            isConnecting = true
            viewModel.selectDevice(device)
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                navigateToDeviceList = true
                isConnecting = false
            }
        }) {
            VStack(alignment: .leading) {
                HStack {
                    Text(device.name)
                        .font(.headline)
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                HStack {
                    Text(device.ip)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f GH/s", device.hashrate))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f°C", device.temperature))
                        .font(.subheadline)
                        .foregroundColor(device.temperature > 80 ? .red : .blue)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.traxeGold, lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func onboardingHeaderAndScanButton() -> some View {
        ParticleSphereView(particleColor: .primary)
            .frame(width: 150, height: 150)

        Text("Connect to device")
            .font(.largeTitle)
            .fontWeight(.bold)
            .fontDesign(.serif)

        Text(viewModel.scanStatus)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)

        if viewModel.isScanning {
            ProgressView()
        } else {
            Button("Scan Network") {
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

    @ViewBuilder
    private func manualEntrySection() -> some View {
        if viewModel.hasScanned {
            VStack(spacing: 12) {
                if viewModel.discoveredDevices.isEmpty {
                    Text("No devices found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 12) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.showManualEntry.toggle()
                        }
                    } label: {
                        HStack {
                            Text("or enter manually".uppercased())
                                .font(.caption)
                            Image(systemName: "chevron.down")
                                .rotationEffect(
                                    .degrees(viewModel.showManualEntry ? 180 : 0)
                                )
                        }
                        .foregroundColor(.secondary)
                    }

                    if viewModel.showManualEntry {
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "network")
                                    .foregroundColor(.secondary)
                                TextField("IP Address", text: $viewModel.manualIPAddress)
                                    .textFieldStyle(.plain)
                                    .keyboardType(.numbersAndPunctuation)
                                    .autocapitalization(.none)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            .padding(.horizontal)

                            Button(action: {
                                guard !isConnecting else { return }
                                isConnecting = true
                                Task {
                                    if await viewModel.connectManually() {
                                        navigateToDeviceList = true
                                    }
                                    isConnecting = false
                                }
                            }) {
                                HStack {
                                    Text("Connect Manually")
                                    Image(systemName: "arrow.right")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.traxeGold)
                            .disabled(viewModel.manualIPAddress.isEmpty)
                        }
                        .transition(.opacity)
                    }
                }
            }
            .padding()
        }
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: HistoricalDataPoint.self, configurations: config)
    let previewDashboardVM = DashboardViewModel(modelContext: container.mainContext)

    return OnboardingView(dashboardViewModel: previewDashboardVM)
        .modelContainer(container)
}
