import XCTest

@testable import Traxe

final class MinerAlertStateMachineTests: XCTestCase {
    func testResponseWithoutHashrateEstablishesReachability() {
        let ipAddress = "192.168.1.10"

        let evaluation = MinerAlertStateMachine.evaluate(
            ipAddresses: [ipAddress],
            respondedIPAddresses: [ipAddress],
            baselineReachableIPAddresses: [],
            fetchedTemperatures: [:],
            hostnames: [:],
            localIPv4Prefixes: ["192.168.1."],
            alertEnabledIPAddresses: [ipAddress],
            referenceDate: Date(timeIntervalSince1970: 1_000),
            initialState: [:]
        )

        XCTAssertTrue(evaluation.state[ipAddress]?.wasReachable == true)
        XCTAssertEqual(evaluation.state[ipAddress]?.consecutiveFailures, 0)
        XCTAssertTrue(evaluation.events.isEmpty)
    }

    func testDisabledRefreshSeedsFirstEnabledOfflineTransition() {
        let ipAddress = "192.168.1.10"
        let initialDate = Date(timeIntervalSince1970: 1_000)
        let seeded = MinerAlertStateMachine.evaluate(
            ipAddresses: [ipAddress],
            respondedIPAddresses: [ipAddress],
            baselineReachableIPAddresses: [],
            fetchedTemperatures: [:],
            hostnames: [ipAddress: "garage"],
            localIPv4Prefixes: ["192.168.1."],
            alertEnabledIPAddresses: [],
            referenceDate: initialDate,
            initialState: [:]
        )
        let firstMiss = MinerAlertStateMachine.evaluate(
            ipAddresses: [ipAddress],
            respondedIPAddresses: [],
            baselineReachableIPAddresses: [],
            fetchedTemperatures: [:],
            hostnames: [ipAddress: "garage"],
            localIPv4Prefixes: ["192.168.1."],
            alertEnabledIPAddresses: [ipAddress],
            referenceDate: initialDate.addingTimeInterval(600),
            initialState: seeded.state
        )
        let secondMiss = MinerAlertStateMachine.evaluate(
            ipAddresses: [ipAddress],
            respondedIPAddresses: [],
            baselineReachableIPAddresses: [],
            fetchedTemperatures: [:],
            hostnames: [ipAddress: "garage"],
            localIPv4Prefixes: ["192.168.1."],
            alertEnabledIPAddresses: [ipAddress],
            referenceDate: initialDate.addingTimeInterval(1_200),
            initialState: firstMiss.state
        )

        XCTAssertTrue(firstMiss.events.isEmpty)
        XCTAssertEqual(
            secondMiss.events,
            [.offline(ipAddress: ipAddress, name: "garage")]
        )
        XCTAssertFalse(secondMiss.state[ipAddress]?.wasReachable == true)
    }

    func testRecentCacheBaselineCanSeedFirstEnabledOfflineTransition() {
        let ipAddress = "192.168.1.10"
        let initialDate = Date(timeIntervalSince1970: 1_000)
        let firstMiss = MinerAlertStateMachine.evaluate(
            ipAddresses: [ipAddress],
            respondedIPAddresses: [],
            baselineReachableIPAddresses: [ipAddress],
            fetchedTemperatures: [:],
            hostnames: [:],
            localIPv4Prefixes: ["192.168.1."],
            alertEnabledIPAddresses: [ipAddress],
            referenceDate: initialDate,
            initialState: [:]
        )
        let secondMiss = MinerAlertStateMachine.evaluate(
            ipAddresses: [ipAddress],
            respondedIPAddresses: [],
            baselineReachableIPAddresses: [],
            fetchedTemperatures: [:],
            hostnames: [:],
            localIPv4Prefixes: ["192.168.1."],
            alertEnabledIPAddresses: [ipAddress],
            referenceDate: initialDate.addingTimeInterval(600),
            initialState: firstMiss.state
        )

        XCTAssertTrue(firstMiss.events.isEmpty)
        XCTAssertEqual(
            secondMiss.events,
            [.offline(ipAddress: ipAddress, name: ipAddress)]
        )
    }

    func testContinuouslyHotMinerAlertsOnceUntilItCools() {
        let ipAddress = "192.168.1.10"
        let initialDate = Date(timeIntervalSince1970: 1_000)
        let firstHot = MinerAlertStateMachine.evaluate(
            ipAddresses: [ipAddress],
            respondedIPAddresses: [ipAddress],
            baselineReachableIPAddresses: [],
            fetchedTemperatures: [ipAddress: 80],
            hostnames: [ipAddress: "garage"],
            localIPv4Prefixes: ["192.168.1."],
            alertEnabledIPAddresses: [ipAddress],
            referenceDate: initialDate,
            initialState: [:]
        )
        let stillHot = MinerAlertStateMachine.evaluate(
            ipAddresses: [ipAddress],
            respondedIPAddresses: [ipAddress],
            baselineReachableIPAddresses: [],
            fetchedTemperatures: [ipAddress: 81],
            hostnames: [ipAddress: "garage"],
            localIPv4Prefixes: ["192.168.1."],
            alertEnabledIPAddresses: [ipAddress],
            referenceDate: initialDate.addingTimeInterval(7 * 60 * 60),
            initialState: firstHot.state
        )
        let cooled = MinerAlertStateMachine.evaluate(
            ipAddresses: [ipAddress],
            respondedIPAddresses: [ipAddress],
            baselineReachableIPAddresses: [],
            fetchedTemperatures: [ipAddress: 70],
            hostnames: [ipAddress: "garage"],
            localIPv4Prefixes: ["192.168.1."],
            alertEnabledIPAddresses: [ipAddress],
            referenceDate: initialDate.addingTimeInterval(8 * 60 * 60),
            initialState: stillHot.state
        )
        let hotAgain = MinerAlertStateMachine.evaluate(
            ipAddresses: [ipAddress],
            respondedIPAddresses: [ipAddress],
            baselineReachableIPAddresses: [],
            fetchedTemperatures: [ipAddress: 82],
            hostnames: [ipAddress: "garage"],
            localIPv4Prefixes: ["192.168.1."],
            alertEnabledIPAddresses: [ipAddress],
            referenceDate: initialDate.addingTimeInterval(9 * 60 * 60),
            initialState: cooled.state
        )

        XCTAssertEqual(
            firstHot.events,
            [.hot(ipAddress: ipAddress, name: "garage", temperature: 80)]
        )
        XCTAssertTrue(stillHot.events.isEmpty)
        XCTAssertTrue(cooled.events.isEmpty)
        XCTAssertEqual(
            hotAgain.events,
            [.hot(ipAddress: ipAddress, name: "garage", temperature: 82)]
        )
    }

    func testEnablingAlertsWhileMinerIsAlreadyHotEmitsAlert() {
        let ipAddress = "192.168.1.10"
        let initialDate = Date(timeIntervalSince1970: 1_000)
        let disabled = MinerAlertStateMachine.evaluate(
            ipAddresses: [ipAddress],
            respondedIPAddresses: [ipAddress],
            baselineReachableIPAddresses: [],
            fetchedTemperatures: [ipAddress: 80],
            hostnames: [ipAddress: "garage"],
            localIPv4Prefixes: ["192.168.1."],
            alertEnabledIPAddresses: [],
            referenceDate: initialDate,
            initialState: [:]
        )
        let enabled = MinerAlertStateMachine.evaluate(
            ipAddresses: [ipAddress],
            respondedIPAddresses: [ipAddress],
            baselineReachableIPAddresses: [],
            fetchedTemperatures: [ipAddress: 80],
            hostnames: [ipAddress: "garage"],
            localIPv4Prefixes: ["192.168.1."],
            alertEnabledIPAddresses: [ipAddress],
            referenceDate: initialDate.addingTimeInterval(600),
            initialState: disabled.state
        )

        XCTAssertTrue(disabled.events.isEmpty)
        XCTAssertEqual(
            enabled.events,
            [.hot(ipAddress: ipAddress, name: "garage", temperature: 80)]
        )
    }

    func testOnlyEnabledMinersEmitOfflineEventsInAMixedFleet() {
        let enabledIPAddress = "192.168.1.10"
        let disabledIPAddress = "192.168.1.11"
        let initialDate = Date(timeIntervalSince1970: 1_000)
        let seeded = MinerAlertStateMachine.evaluate(
            ipAddresses: [enabledIPAddress, disabledIPAddress],
            respondedIPAddresses: [enabledIPAddress, disabledIPAddress],
            baselineReachableIPAddresses: [],
            fetchedTemperatures: [:],
            hostnames: [enabledIPAddress: "garage", disabledIPAddress: "closet"],
            localIPv4Prefixes: ["192.168.1."],
            alertEnabledIPAddresses: [enabledIPAddress],
            referenceDate: initialDate,
            initialState: [:]
        )
        let firstMiss = MinerAlertStateMachine.evaluate(
            ipAddresses: [enabledIPAddress, disabledIPAddress],
            respondedIPAddresses: [],
            baselineReachableIPAddresses: [],
            fetchedTemperatures: [:],
            hostnames: [enabledIPAddress: "garage", disabledIPAddress: "closet"],
            localIPv4Prefixes: ["192.168.1."],
            alertEnabledIPAddresses: [enabledIPAddress],
            referenceDate: initialDate.addingTimeInterval(600),
            initialState: seeded.state
        )
        let secondMiss = MinerAlertStateMachine.evaluate(
            ipAddresses: [enabledIPAddress, disabledIPAddress],
            respondedIPAddresses: [],
            baselineReachableIPAddresses: [],
            fetchedTemperatures: [:],
            hostnames: [enabledIPAddress: "garage", disabledIPAddress: "closet"],
            localIPv4Prefixes: ["192.168.1."],
            alertEnabledIPAddresses: [enabledIPAddress],
            referenceDate: initialDate.addingTimeInterval(1_200),
            initialState: firstMiss.state
        )

        XCTAssertTrue(firstMiss.events.isEmpty)
        XCTAssertEqual(
            secondMiss.events,
            [.offline(ipAddress: enabledIPAddress, name: "garage")]
        )
        // The disabled miner keeps tracking health so it can alert immediately after
        // the user opts in.
        XCTAssertEqual(secondMiss.state[disabledIPAddress]?.consecutiveFailures, 2)
        XCTAssertTrue(secondMiss.state[disabledIPAddress]?.wasReachable == true)
    }

    func testDisabledHotMinerStaysSilentWhileAnEnabledHotMinerAlerts() {
        let enabledIPAddress = "192.168.1.10"
        let disabledIPAddress = "192.168.1.11"

        let evaluation = MinerAlertStateMachine.evaluate(
            ipAddresses: [enabledIPAddress, disabledIPAddress],
            respondedIPAddresses: [enabledIPAddress, disabledIPAddress],
            baselineReachableIPAddresses: [],
            fetchedTemperatures: [enabledIPAddress: 80, disabledIPAddress: 90],
            hostnames: [enabledIPAddress: "garage", disabledIPAddress: "closet"],
            localIPv4Prefixes: ["192.168.1."],
            alertEnabledIPAddresses: [enabledIPAddress],
            referenceDate: Date(timeIntervalSince1970: 1_000),
            initialState: [:]
        )

        XCTAssertEqual(
            evaluation.events,
            [.hot(ipAddress: enabledIPAddress, name: "garage", temperature: 80)]
        )
        XCTAssertNil(evaluation.state[disabledIPAddress]?.lastHotAlert)
    }

    func testNoMinerAlertsWhenNoMinerIsEnabled() {
        let firstIPAddress = "192.168.1.10"
        let secondIPAddress = "192.168.1.11"
        let initialDate = Date(timeIntervalSince1970: 1_000)
        let seeded = MinerAlertStateMachine.evaluate(
            ipAddresses: [firstIPAddress, secondIPAddress],
            respondedIPAddresses: [firstIPAddress, secondIPAddress],
            baselineReachableIPAddresses: [],
            fetchedTemperatures: [firstIPAddress: 90],
            hostnames: [:],
            localIPv4Prefixes: ["192.168.1."],
            alertEnabledIPAddresses: [],
            referenceDate: initialDate,
            initialState: [:]
        )
        let firstMiss = MinerAlertStateMachine.evaluate(
            ipAddresses: [firstIPAddress, secondIPAddress],
            respondedIPAddresses: [],
            baselineReachableIPAddresses: [],
            fetchedTemperatures: [:],
            hostnames: [:],
            localIPv4Prefixes: ["192.168.1."],
            alertEnabledIPAddresses: [],
            referenceDate: initialDate.addingTimeInterval(600),
            initialState: seeded.state
        )
        let secondMiss = MinerAlertStateMachine.evaluate(
            ipAddresses: [firstIPAddress, secondIPAddress],
            respondedIPAddresses: [],
            baselineReachableIPAddresses: [],
            fetchedTemperatures: [:],
            hostnames: [:],
            localIPv4Prefixes: ["192.168.1."],
            alertEnabledIPAddresses: [],
            referenceDate: initialDate.addingTimeInterval(1_200),
            initialState: firstMiss.state
        )

        XCTAssertTrue(seeded.events.isEmpty)
        XCTAssertTrue(firstMiss.events.isEmpty)
        XCTAssertTrue(secondMiss.events.isEmpty)
    }
}
