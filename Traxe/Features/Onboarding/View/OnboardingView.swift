import SwiftData
import SwiftUI

struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
    @State private var navigateToDeviceList = false
    @State private var showSettingsAlert = false
    @State private var showConnectionError = false
    @State private var connectionError = ""
    let dashboardViewModel: DashboardViewModel
    @State private var pulse = false
    @State private var isConnecting = false

    private let privacyPolicyURL = URL(string: "https://matthewramsden.com/privacy")
    private let termsOfUseURL = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )

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

                    if let privacyPolicyURL, let termsOfUseURL {
                        HStack(spacing: 4) {
                            Link("Privacy Policy", destination: privacyPolicyURL)
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Link("Terms of Use", destination: termsOfUseURL)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    }

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
                        "Traxe needs access to your local network to find miners. Please enable it in Settings."
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
    }

    private func deviceRow(_ device: DiscoveredDevice) -> some View {
        Button(action: {
            guard !isConnecting else { return }
            isConnecting = true
            viewModel.selectDevice(device)
            Task {
                try? await Task.sleep(for: .milliseconds(200))
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

        Text("Connect to miner")
            .font(.largeTitle)
            .fontWeight(.bold)
            .fontDesign(.serif)

        Text(viewModel.scanStatus)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)

        if viewModel.isScanning {
            ProgressView()
        } else {

            if #available(iOS 26.0, *) {
                Button("Scan Network") {
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

        if !viewModel.detectedNetworkInfo.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "network")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(viewModel.detectedNetworkInfo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func manualEntrySection() -> some View {
        if viewModel.hasScanned {
            VStack(spacing: 12) {
                if viewModel.discoveredDevices.isEmpty {
                    Text("No miners found")
                        .font(.headline)
                        .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                    }

                    if viewModel.showManualEntry {
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "network")
                                    .foregroundStyle(.secondary)
                                TextField("IP Address", text: $viewModel.manualIPAddress)
                                    .textFieldStyle(.plain)
                                    .keyboardType(.numbersAndPunctuation)
                                    .autocapitalization(.none)
                            }
                            .padding()
                            .background(Color(uiColor: .systemGray6))
                            .clipShape(.rect(cornerRadius: 10))
                            .padding(.horizontal)

                            if #available(iOS 26.0, *) {
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
                                .buttonStyle(.glassProminent)
                                .tint(Color.traxeGold)
                                .disabled(viewModel.manualIPAddress.isEmpty)
                            } else {
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
    let container = makeOnboardingPreviewContainer(config: config)
    let previewDashboardVM = DashboardViewModel(modelContext: container.mainContext)

    return OnboardingView(dashboardViewModel: previewDashboardVM)
        .modelContainer(container)
}

private func makeOnboardingPreviewContainer(config: ModelConfiguration) -> ModelContainer {
    do {
        return try ModelContainer(for: HistoricalDataPoint.self, configurations: config)
    } catch {
        fatalError("Failed to create onboarding preview container: \(error)")
    }
}
