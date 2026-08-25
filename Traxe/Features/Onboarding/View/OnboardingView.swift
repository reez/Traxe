import SwiftData
import SwiftUI

struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
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
                // Scrolls when the content is taller than the window (short landscape
                // windows, large text) and stays vertically centered when it is not.
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 20) {
                            Spacer()
                            Spacer().frame(height: 20)

                            onboardingHeaderAndScanButton()

                            if !viewModel.discoveredDevices.isEmpty {
                                VStack(spacing: 8) {
                                    ForEach(viewModel.discoveredDevices) { device in
                                        deviceRow(device)
                                    }
                                }
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
                        .frame(maxWidth: 700)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    }
                }
                .animation(.easeInOut, value: viewModel.isScanning)
                .navigationTitle("Welcome")
                .toolbar(.hidden, for: .navigationBar)
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
                        "Traxe needs access to your local network to find miners. Enable Local Network access in Settings."
                    )
                }
                .alert("Connection Error", isPresented: $showConnectionError) {
                    Button("OK") {}
                } message: {
                    Text(connectionError)
                }
            }
        }
    }

    private func deviceRow(_ device: DiscoveredDevice) -> some View {
        Button(action: {
            guard !isConnecting else { return }
            isConnecting = true
            guard viewModel.selectDevice(device) else {
                isConnecting = false
                return
            }
            Task {
                try? await Task.sleep(for: .milliseconds(200))
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
    }

    @ViewBuilder
    private func onboardingHeaderAndScanButton() -> some View {
        ParticleSphereView(particleColor: .primary)
            .frame(width: 150, height: 150)

        Text("Add a Miner")
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

            Button("Scan for Miners") {
                Task {
                    let result = await viewModel.startScan()
                    if result == .permissionDenied {
                        self.showSettingsAlert = true
                    }
                }
            }
            .prominentActionButtonStyle()
            .tint(Color.traxeGold)
            .disabled(viewModel.isScanning)

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
                            Text("or enter an IP address".uppercased())
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

                            Button(action: {
                                guard !isConnecting else { return }
                                isConnecting = true
                                Task {
                                    _ = await viewModel.connectManually()
                                    isConnecting = false
                                }
                            }) {
                                HStack {
                                    Text("Add Miner")
                                    Image(systemName: "arrow.right")
                                }
                            }
                            .prominentActionButtonStyle()
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
