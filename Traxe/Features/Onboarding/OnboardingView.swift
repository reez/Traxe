import SwiftData
import SwiftUI

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @State private var navigateToDashboard = false
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

                ParticleSphereView(particleColor: .primary)
                    .frame(width: 150, height: 150)

                Text("Connect to BitAxe")
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
                        if !viewModel.hasLocalNetworkPermission {
                            showSettingsAlert = true
                        } else {
                            Task {
                                await viewModel.startScan()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.traxeGold)
                    .disabled(viewModel.isScanning)
                }

                // List of discovered devices
                if !viewModel.discoveredDevices.isEmpty {
                    List(viewModel.discoveredDevices) { device in
                        Button(action: {
                            guard !isConnecting else { return }
                            isConnecting = true
                            viewModel.selectDevice(device)
                            Task {
                                // Add a small delay before connecting
                                try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2 seconds
                                await dashboardViewModel.connect()
                                navigateToDashboard = true
                                //                                } catch {
                                //                                    connectionError = error.localizedDescription
                                //                                    showConnectionError = true
                                //                                }
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
                    .listStyle(.plain)
                    .frame(height: CGFloat(viewModel.discoveredDevices.count) * 80)
                }

                // Manual IP entry - only show after scanning
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
                                    Text("(or enter manually)")
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
                                            // Await the result of connectManually
                                            if await viewModel.connectManually() {
                                                // If successful, THEN connect and navigate
                                                await dashboardViewModel.connect()
                                                navigateToDashboard = true
                                            }
                                            // Ensure isConnecting is reset regardless of success
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

                Spacer()
            }
            .padding()
            .animation(.easeInOut, value: viewModel.isScanning)
            .navigationTitle("Welcome")
            .navigationBarHidden(true)
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
                    "Traxe needs access to your local network to find BitAxe devices. Please enable it in Settings."
                )
            }
            .alert("Connection Error", isPresented: $showConnectionError) {
                Button("OK") {}
            } message: {
                Text(connectionError)
            }
            .navigationDestination(isPresented: $navigateToDashboard) {
                DashboardView(viewModel: dashboardViewModel)
            }
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
    // Preview needs a dummy DashboardViewModel and ModelContainer
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: HistoricalDataPoint.self, configurations: config)
    let previewDashboardVM = DashboardViewModel(modelContext: container.mainContext)

    return OnboardingView(dashboardViewModel: previewDashboardVM)
        .modelContainer(container)
}
