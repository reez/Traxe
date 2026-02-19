import Foundation
import XCTest

@testable import Traxe

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    private let permissionDeniedMessage =
        "Please allow local network access in Settings to scan for miners"

    func testStartScanReturnsPermissionDeniedWhenProbeReportsOffline() async {
        let checkedIPs = LockedBox<[String]>([])
        var dependencies = makeBaseDependencies()
        dependencies.urlSession = .init(data: { _ in
            throw URLError(.notConnectedToInternet)
        })
        dependencies.deviceManagement = .init(
            checkDevice: { ip in
                checkedIPs.withValue { $0.append(ip) }
                throw DeviceCheckError.requestFailed(.timedOut)
            },
            saveDevice: { _ in }
        )

        let viewModel = OnboardingViewModel(dependencies: dependencies)
        let result = await viewModel.startScan()

        guard case .permissionDenied = result else {
            XCTFail("Expected permissionDenied when local network probe reports offline")
            return
        }

        XCTAssertFalse(viewModel.isScanning)
        XCTAssertTrue(viewModel.hasScanned)
        XCTAssertFalse(viewModel.hasLocalNetworkPermission)
        XCTAssertEqual(viewModel.scanStatus, permissionDeniedMessage)
        XCTAssertTrue(checkedIPs.value.isEmpty)
    }

    func testTimedOutHostsDoNotTriggerPermissionDeniedDuringSubnetScan() async {
        let checkedIPs = LockedBox<[String]>([])
        var dependencies = makeBaseDependencies()
        dependencies.urlSession = .init(data: { _ in
            throw URLError(.timedOut)
        })
        dependencies.networkInterfaces = { ["192.168.50.11"] }
        dependencies.scanHostRange = 1...3
        dependencies.scanTimeout = .milliseconds(20)
        dependencies.sleep = { duration in
            try? await Task.sleep(for: duration)
        }
        dependencies.deviceManagement = .init(
            checkDevice: { ip in
                checkedIPs.withValue { $0.append(ip) }
                throw DeviceCheckError.requestFailed(.timedOut)
            },
            saveDevice: { _ in }
        )

        let viewModel = OnboardingViewModel(dependencies: dependencies)
        let result = await viewModel.startScan()

        guard case .success = result else {
            XCTFail("Expected scan to begin when probe indicates permission is available")
            return
        }

        try? await Task.sleep(for: .milliseconds(120))

        XCTAssertTrue(viewModel.hasLocalNetworkPermission)
        XCTAssertNotEqual(viewModel.scanStatus, permissionDeniedMessage)
        XCTAssertFalse(viewModel.isScanning)
        XCTAssertTrue(viewModel.hasScanned)
        XCTAssertFalse(checkedIPs.value.isEmpty)
    }

    func testConnectManuallyUsesInjectedCheckAndSave() async {
        let checkedIPs = LockedBox<[String]>([])
        let savedDevices = LockedBox<[SavedDevice]>([])
        var dependencies = makeBaseDependencies()
        dependencies.urlSession = .init(data: { _ in
            throw URLError(.timedOut)
        })
        dependencies.deviceManagement = .init(
            checkDevice: { ip in
                checkedIPs.withValue { $0.append(ip) }
                return Self.makeDiscoveredDevice(ip: ip)
            },
            saveDevice: { device in
                savedDevices.withValue { $0.append(device) }
            }
        )

        let viewModel = OnboardingViewModel(dependencies: dependencies)
        viewModel.manualIPAddress = " 192.168.1.44 "

        let didConnect = await viewModel.connectManually()

        XCTAssertTrue(didConnect)
        XCTAssertEqual(checkedIPs.value, ["192.168.1.44"])
        XCTAssertEqual(savedDevices.value.map(\.ipAddress), ["192.168.1.44"])
        XCTAssertEqual(viewModel.discoveredDevices.map(\.ip), ["192.168.1.44"])
    }

    private func makeBaseDependencies() -> OnboardingViewModel.Dependencies {
        var dependencies = OnboardingViewModel.Dependencies.live
        dependencies.notificationCenter = NotificationCenter()
        dependencies.scanTimeout = .milliseconds(50)
        dependencies.sleep = { duration in
            try? await Task.sleep(for: duration)
        }
        dependencies.networkInterfaces = { ["192.168.1.10"] }
        dependencies.scanHostRange = 1...2
        dependencies.deviceManagement = .init(
            checkDevice: { _ in
                throw DeviceCheckError.notBitaxeDevice
            },
            saveDevice: { _ in }
        )
        return dependencies
    }

    nonisolated private static func makeDiscoveredDevice(ip: String) -> DiscoveredDevice {
        DiscoveredDevice(
            ip: ip,
            name: "Test Miner",
            hashrate: 1.5,
            temperature: 48.0,
            bestDiff: "1 K",
            power: 12.0,
            poolURL: "stratum+tcp://pool.example.com",
            blockHeight: 1,
            networkDifficulty: 1
        )
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&storedValue)
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }
}
