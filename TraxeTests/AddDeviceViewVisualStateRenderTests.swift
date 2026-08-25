import SwiftUI
import XCTest

@testable import Traxe

@MainActor
final class AddDeviceViewVisualStateRenderTests: XCTestCase {
    private let pointSize = CGSize(width: 393, height: 852)
    private let scale: CGFloat = 3

    func testRenderBatchSelectionStates() async throws {
        guard visualStateRenderingEnabled else {
            throw XCTSkip("Set RENDER_ADD_DEVICE_VISUAL_STATES=1 to render visual QA states.")
        }

        let outputDirectory = try makeOutputDirectory()
        let devices = Self.sampleDevices

        try await render(
            filename: "01-scan-results-one-slot-none-selected.png",
            outputDirectory: outputDirectory,
            view: await makeAddDeviceView(
                devices: devices,
                deviceLimit: 1,
                selectedDeviceIPs: []
            )
        )

        try await render(
            filename: "02-one-slot-cap-reached.png",
            outputDirectory: outputDirectory,
            view: await makeAddDeviceView(
                devices: devices,
                deviceLimit: 1,
                selectedDeviceIPs: [devices[0].ip]
            )
        )

        try await render(
            filename: "03-miners-five-multiple-selected.png",
            outputDirectory: outputDirectory,
            view: await makeAddDeviceView(
                devices: devices,
                deviceLimit: 5,
                selectedDeviceIPs: [devices[0].ip, devices[1].ip, devices[2].ip]
            )
        )

        try await render(
            filename: "04-miners-five-cap-reached.png",
            outputDirectory: outputDirectory,
            view: await makeAddDeviceView(
                devices: devices,
                existingDeviceIPs: [devices[0].ip, devices[1].ip],
                deviceLimit: 5,
                selectedDeviceIPs: [devices[2].ip, devices[3].ip, devices[4].ip]
            )
        )

        try await render(
            filename: "05-pro-select-all.png",
            outputDirectory: outputDirectory,
            view: await makeAddDeviceView(
                devices: devices,
                deviceLimit: Int.max,
                selectedDeviceIPs: Set(devices.map(\.ip))
            )
        )
    }

    private var visualStateRenderingEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["RENDER_ADD_DEVICE_VISUAL_STATES"] == "1"
            || environment["TEST_RUNNER_RENDER_ADD_DEVICE_VISUAL_STATES"] == "1"
    }

    private func makeOutputDirectory() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let outputPath =
            environment["ADD_DEVICE_VISUAL_STATES_DIR"]
            ?? environment["TEST_RUNNER_ADD_DEVICE_VISUAL_STATES_DIR"]
            ?? "screenshots/visual-qa/add-miner-states"

        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: outputURL,
            withIntermediateDirectories: true
        )
        return outputURL
    }

    private func makeAddDeviceView(
        devices: [DiscoveredDevice],
        existingDeviceIPs: Set<String> = [],
        deviceLimit: Int,
        selectedDeviceIPs: Set<String>
    ) async -> some View {
        let viewModel = OnboardingViewModel(dependencies: makePreviewDependencies())
        try? await Task.sleep(for: .milliseconds(20))
        viewModel.hasLocalNetworkPermission = true
        viewModel.hasScanned = true
        viewModel.scanStatus = "Scan complete. Found \(devices.count) miners."
        viewModel.discoveredDevices = devices

        return AddDeviceView(
            existingDeviceIPs: existingDeviceIPs,
            deviceLimit: deviceLimit,
            viewModel: viewModel,
            selectedDeviceIPs: selectedDeviceIPs
        )
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.large)
    }

    private func makePreviewDependencies() -> OnboardingViewModel.Dependencies {
        var dependencies = OnboardingViewModel.Dependencies.live
        dependencies.notificationCenter = NotificationCenter()
        dependencies.urlSession = .init(data: { _ in
            throw URLError(.timedOut)
        })
        dependencies.sleep = { _ in }
        dependencies.networkInterfaces = { ["192.168.4.10"] }
        dependencies.scanHostRange = 1...1
        dependencies.deviceManagement = .init(
            checkDevice: { _ in
                throw DeviceCheckError.notBitaxeDevice
            },
            saveDevice: { _ in },
            saveDevices: { _ in }
        )
        return dependencies
    }

    private func render<Content: View>(
        filename: String,
        outputDirectory: URL,
        view: Content
    ) async throws {
        let rootView =
            view
            .frame(width: pointSize.width, height: pointSize.height)
        let host = UIHostingController(rootView: rootView)
        host.overrideUserInterfaceStyle = .dark

        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first
        {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: pointSize))
        }

        window.frame = CGRect(origin: .zero, size: pointSize)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.backgroundColor = .black
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        try await Task.sleep(for: .milliseconds(200))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: pointSize, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }

        guard let data = image.pngData()
        else {
            XCTFail("Failed to render \(filename)")
            return
        }

        let outputURL = outputDirectory.appendingPathComponent(filename)
        try data.write(to: outputURL, options: [.atomic])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        window.isHidden = true
    }

    private static let sampleDevices: [DiscoveredDevice] = [
        DiscoveredDevice(
            ip: "192.168.4.187",
            name: "bitaxe-205",
            hashrate: 415.8,
            temperature: 60.0,
            bestDiff: "1.2M",
            power: 16.8,
            poolURL: nil,
            blockHeight: nil,
            networkDifficulty: nil
        ),
        DiscoveredDevice(
            ip: "192.168.4.188",
            name: "bitaxe-601",
            hashrate: 138.9,
            temperature: 57.0,
            bestDiff: "820K",
            power: 12.1,
            poolURL: nil,
            blockHeight: nil,
            networkDifficulty: nil
        ),
        DiscoveredDevice(
            ip: "192.168.4.186",
            name: "nerdqaxe++",
            hashrate: 4_899.2,
            temperature: 61.9,
            bestDiff: "6.4M",
            power: 72.0,
            poolURL: nil,
            blockHeight: nil,
            networkDifficulty: nil
        ),
        DiscoveredDevice(
            ip: "192.168.4.189",
            name: "bitaxe-601",
            hashrate: 534.2,
            temperature: 55.9,
            bestDiff: "2.0M",
            power: 18.0,
            poolURL: nil,
            blockHeight: nil,
            networkDifficulty: nil
        ),
        DiscoveredDevice(
            ip: "192.168.4.185",
            name: "lucky x5",
            hashrate: 2_682.4,
            temperature: 60.0,
            bestDiff: "5.7M",
            power: 60.4,
            poolURL: nil,
            blockHeight: nil,
            networkDifficulty: nil
        ),
    ]
}
