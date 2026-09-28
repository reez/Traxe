import Foundation
import XCTest

@testable import Traxe

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    private let permissionDeniedMessage =
        "Allow Local Network access in Settings to scan for miners"

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
            saveDevice: { _ in },
            saveDevices: { _ in }
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

    func testStartScanKeepsManualEntryAvailableWhenNoNetworkInterfaceIsFound() async {
        let checkedIPs = LockedBox<[String]>([])
        var dependencies = makeBaseDependencies()
        dependencies.urlSession = .init(data: { _ in
            throw URLError(.timedOut)
        })
        dependencies.networkInterfaces = { [] }
        dependencies.deviceManagement = .init(
            checkDevice: { ip in
                checkedIPs.withValue { $0.append(ip) }
                throw DeviceCheckError.notBitaxeDevice
            },
            saveDevice: { _ in },
            saveDevices: { _ in }
        )

        let viewModel = OnboardingViewModel(dependencies: dependencies)
        let result = await viewModel.startScan()

        guard case .networkUnavailable = result else {
            XCTFail("Expected an unavailable network instead of a permission denial")
            return
        }
        XCTAssertTrue(viewModel.hasScanned)
        XCTAssertFalse(viewModel.isScanning)
        XCTAssertTrue(viewModel.hasLocalNetworkPermission)
        XCTAssertTrue(viewModel.showErrorAlert)
        XCTAssertEqual(
            viewModel.errorMessage,
            "Could not determine a local network interface to scan."
        )
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
            saveDevice: { _ in },
            saveDevices: { _ in }
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
            },
            saveDevices: { _ in }
        )

        let viewModel = OnboardingViewModel(dependencies: dependencies)
        viewModel.manualIPAddress = " 192.168.1.44 "

        let didConnect = await viewModel.connectManually()

        XCTAssertTrue(didConnect)
        XCTAssertEqual(checkedIPs.value, ["192.168.1.44"])
        XCTAssertEqual(savedDevices.value.map(\.ipAddress), ["192.168.1.44"])
        XCTAssertEqual(viewModel.discoveredDevices.map(\.ip), ["192.168.1.44"])
    }

    func testCancelledManualAddDoesNotSaveAResponseThatArrivesAfterCancellation() async throws {
        let checkStarted = expectation(description: "Manual device check started")
        let pendingResponse = LockedBox<CheckedContinuation<DiscoveredDevice, Never>?>(nil)
        let savedDevices = LockedBox<[SavedDevice]>([])
        var dependencies = makeBaseDependencies()
        dependencies.urlSession = .init(data: { _ in
            throw URLError(.timedOut)
        })
        dependencies.deviceManagement = .init(
            checkDevice: { _ in
                await withCheckedContinuation { continuation in
                    pendingResponse.withValue { $0 = continuation }
                    checkStarted.fulfill()
                }
            },
            saveDevice: { device in
                savedDevices.withValue { $0.append(device) }
            },
            saveDevices: { _ in }
        )
        let viewModel = OnboardingViewModel(dependencies: dependencies)
        let request = Task {
            try await viewModel.checkAndSaveDevice(ip: "192.168.1.44")
        }
        await fulfillment(of: [checkStarted], timeout: 1)

        request.cancel()
        let response = try XCTUnwrap(pendingResponse.value)
        response.resume(returning: Self.makeDiscoveredDevice(ip: "192.168.1.44"))
        do {
            _ = try await request.value
            XCTFail("A cancelled manual add must not save its late response")
        } catch is CancellationError {
        }

        XCTAssertTrue(savedDevices.value.isEmpty)
        XCTAssertFalse(viewModel.showErrorAlert)
    }

    func testSelectDeviceReturnsFalseWhenSaveFails() {
        var dependencies = makeBaseDependencies()
        dependencies.deviceManagement = .init(
            checkDevice: { _ in
                XCTFail(
                    "checkDevice should not be called when selecting an existing discovery result"
                )
                throw DeviceCheckError.notBitaxeDevice
            },
            saveDevice: { _ in
                throw NSError(domain: "OnboardingViewModelTests", code: 1)
            },
            saveDevices: { _ in
                throw NSError(domain: "OnboardingViewModelTests", code: 1)
            }
        )

        let viewModel = OnboardingViewModel(dependencies: dependencies)
        let didSave = viewModel.selectDevice(Self.makeDiscoveredDevice(ip: "192.168.1.55"))

        XCTAssertFalse(didSave)
        XCTAssertTrue(viewModel.showErrorAlert)
        XCTAssertEqual(
            viewModel.errorMessage,
            "Failed to save the selected miner. Please try again."
        )
    }

    func testSelectDevicesUsesBatchSave() {
        let savedDeviceBatches = LockedBox<[[SavedDevice]]>([])
        var dependencies = makeBaseDependencies()
        dependencies.deviceManagement = .init(
            checkDevice: { _ in
                XCTFail(
                    "checkDevice should not be called when selecting existing discovery results"
                )
                throw DeviceCheckError.notBitaxeDevice
            },
            saveDevice: { _ in
                XCTFail("saveDevice should not be called for batch selection")
            },
            saveDevices: { devices in
                savedDeviceBatches.withValue { $0.append(devices) }
            }
        )

        let viewModel = OnboardingViewModel(dependencies: dependencies)
        let didSave = viewModel.selectDevices([
            Self.makeDiscoveredDevice(ip: "192.168.1.55"),
            Self.makeDiscoveredDevice(ip: "192.168.1.56"),
        ])

        XCTAssertTrue(didSave)
        XCTAssertEqual(savedDeviceBatches.value.count, 1)
        XCTAssertEqual(
            savedDeviceBatches.value.first?.map(\.ipAddress),
            ["192.168.1.55", "192.168.1.56"]
        )
    }

    func testSelectDevicesReturnsFalseWhenBatchSaveFails() {
        var dependencies = makeBaseDependencies()
        dependencies.deviceManagement = .init(
            checkDevice: { _ in
                XCTFail(
                    "checkDevice should not be called when selecting existing discovery results"
                )
                throw DeviceCheckError.notBitaxeDevice
            },
            saveDevice: { _ in },
            saveDevices: { _ in
                throw NSError(domain: "OnboardingViewModelTests", code: 1)
            }
        )

        let viewModel = OnboardingViewModel(dependencies: dependencies)
        let didSave = viewModel.selectDevices([
            Self.makeDiscoveredDevice(ip: "192.168.1.55")
        ])

        XCTAssertFalse(didSave)
        XCTAssertTrue(viewModel.showErrorAlert)
        XCTAssertEqual(
            viewModel.errorMessage,
            "Failed to save the selected miners. Please try again."
        )
    }

    func testNotConnectedToInternetDuringSubnetScanDoesNotTriggerPermissionDenied() async {
        let checkedIPs = LockedBox<[String]>([])
        var dependencies = makeBaseDependencies()
        dependencies.urlSession = .init(data: { _ in
            throw URLError(.timedOut)
        })
        dependencies.networkInterfaces = { ["192.168.60.11"] }
        dependencies.scanHostRange = 1...3
        dependencies.scanTimeout = .milliseconds(20)
        dependencies.sleep = { duration in
            try? await Task.sleep(for: duration)
        }
        dependencies.deviceManagement = .init(
            checkDevice: { ip in
                checkedIPs.withValue { $0.append(ip) }
                throw DeviceCheckError.requestFailed(.notConnectedToInternet)
            },
            saveDevice: { _ in },
            saveDevices: { _ in }
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
            saveDevice: { _ in },
            saveDevices: { _ in }
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
