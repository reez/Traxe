import Foundation
import XCTest

@testable import Traxe

final class NumericalTelemetrySafetyTests: XCTestCase {
    func testFlexibleTelemetryTreatsNonfiniteStringsAsUnavailable() throws {
        for value in ["nan", "NaN", "inf", "+inf", "-inf", "Infinity", "-Infinity", "1e999"] {
            let payload = """
                {"hostname":"axe","hashRate":"\(value)","temp":"\(value)","power":"\(value)","errorPercentage":"\(value)","networkDifficulty":"\(value)"}
                """
            let telemetry = try JSONDecoder().decode(
                MinerTelemetryDTO.self,
                from: Data(payload.utf8)
            )
            XCTAssertNil(telemetry.hashrate, value)
            XCTAssertNil(telemetry.temperature, value)
            XCTAssertNil(telemetry.power, value)
            XCTAssertNil(telemetry.errorPercentage, value)
            XCTAssertNil(telemetry.networkDifficulty, value)
            let metrics = DeviceMetrics(from: telemetry)
            XCTAssertFalse(metrics.isHashrateKnown, value)
            XCTAssertFalse(metrics.isTemperatureKnown, value)
        }
    }

    func testBothDecodersRejectNonfiniteDoubleValuesFromDecoderStrategy() throws {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        for value in ["Infinity", "-Infinity", "NaN"] {
            let payload = """
                {"hostname":"axe","hashRate":"\(value)","temp":"\(value)","vrTemp":"\(value)","power":"\(value)","errorPercentage":"\(value)","networkDifficulty":"\(value)"}
                """
            let data = Data(payload.utf8)
            let telemetry = try decoder.decode(MinerTelemetryDTO.self, from: data)
            let system = try decoder.decode(SystemInfoDTO.self, from: data)
            XCTAssertNil(telemetry.hashrate, value)
            XCTAssertNil(telemetry.temperature, value)
            XCTAssertNil(telemetry.power, value)
            XCTAssertNil(system.hashrate, value)
            XCTAssertNil(system.temperature, value)
            XCTAssertNil(system.vrTemp, value)
            XCTAssertNil(system.power, value)
            XCTAssertNil(system.errorPercentage, value)
            XCTAssertNil(system.networkDifficulty, value)
        }
    }

    func testFiniteNumbersRemainMeasuredIncludingZeroAndLargestFiniteValue() throws {
        for (value, expectedHashrate) in [
            (0.0, 0.0),
            (55.75, 55.75),
            (Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude / 1_000),
        ] {
            let data = Data("{\"hashRate\":\(value),\"temp\":\(value),\"power\":\(value)}".utf8)
            let telemetry = try JSONDecoder().decode(MinerTelemetryDTO.self, from: data)
            let system = try JSONDecoder().decode(SystemInfoDTO.self, from: data)
            XCTAssertEqual(telemetry.hashRate, value)
            XCTAssertEqual(telemetry.hashrate, expectedHashrate)
            XCTAssertEqual(telemetry.temperature, value)
            XCTAssertEqual(telemetry.power, value)
            XCTAssertEqual(system.hashRate, value)
            XCTAssertEqual(system.hashrate, expectedHashrate)
            XCTAssertEqual(system.temperature, value)
            XCTAssertEqual(system.power, value)
            XCTAssertTrue(DeviceMetrics(from: telemetry).isTemperatureKnown)
        }
        let strings = try JSONDecoder().decode(
            MinerTelemetryDTO.self,
            from: Data(#"{"hashRate":" 555.5 ","temp":"65.5","power":"0"}"#.utf8)
        )
        XCTAssertEqual(strings.hashrate, 555.5)
        XCTAssertEqual(strings.temperature, 65.5)
        XCTAssertEqual(strings.power, 0)
    }

    func testInvalidTemperatureDoesNotCreateOrResetAnAlertTransition() {
        let ip = "192.168.1.10"
        for temperature in [Double.nan, .infinity, -.infinity] {
            for wasHot in [false, true] {
                let state = MinerAlertDeviceState(wasReachable: true, wasHot: wasHot)
                let result = MinerAlertStateMachine.evaluate(
                    ipAddresses: [ip],
                    respondedIPAddresses: [ip],
                    baselineReachableIPAddresses: [ip],
                    fetchedTemperatures: [ip: temperature],
                    hostnames: [:],
                    localIPv4Prefixes: ["192.168.1."],
                    alertEnabledIPAddresses: [ip],
                    referenceDate: Date(),
                    initialState: [ip: state]
                )
                XCTAssertTrue(result.events.isEmpty)
                XCTAssertEqual(result.state[ip]?.wasHot, wasHot)
            }
        }
        let finite = MinerAlertStateMachine.evaluate(
            ipAddresses: [ip],
            respondedIPAddresses: [ip],
            baselineReachableIPAddresses: [ip],
            fetchedTemperatures: [ip: .greatestFiniteMagnitude],
            hostnames: [:],
            localIPv4Prefixes: ["192.168.1."],
            alertEnabledIPAddresses: [ip],
            referenceDate: Date(),
            initialState: [:]
        )
        XCTAssertEqual(
            finite.events,
            [.hot(ipAddress: ip, name: ip, temperature: .greatestFiniteMagnitude)]
        )
    }

    func testDeviceSummaryKeepsInvalidReadingsUnavailableAndFormatsLargeFiniteValues() async throws
    {
        final class TelemetryProtocol: URLProtocol {
            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
            override func startLoading() {
                guard let url = request.url,
                    let response = HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )
                else { return }
                let payload: String
                switch url.host {
                case "192.0.2.1":
                    payload = #"{"hostname":"axe","hashRate":"nan","temp":"inf","power":"-inf"}"#
                case "192.0.2.2":
                    payload =
                        "{\"hostname\":\"axe\",\"hashRate\":500,\"temp\":\(Double.greatestFiniteMagnitude),\"power\":\(Double.greatestFiniteMagnitude)}"
                default:
                    payload = #"{"hostname":"axe","hashRate":500,"temp":65.9,"power":15.9}"#
                }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(payload.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }
            override func stopLoading() {}
        }
        let previousAISetting = UserDefaults.standard.object(forKey: "ai_enabled")
        UserDefaults.standard.set(false, forKey: "ai_enabled")
        defer {
            if let previousAISetting {
                UserDefaults.standard.set(previousAISetting, forKey: "ai_enabled")
            } else {
                UserDefaults.standard.removeObject(forKey: "ai_enabled")
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TelemetryProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = AIAnalysisService(networkService: NetworkService(session: session))
        let invalid = try await service.generateDeviceSummary(forDevice: "192.0.2.1")
        XCTAssertTrue(invalid.content.contains("hash rate is unavailable"))
        XCTAssertTrue(invalid.content.contains("temperature unavailable"))
        XCTAssertTrue(invalid.content.contains("power unavailable"))
        XCTAssertFalse(invalid.content.contains("0°C"))
        XCTAssertFalse(invalid.content.contains("0W"))

        let large = try await service.generateDeviceSummary(forDevice: "192.0.2.2")
        XCTAssertTrue(large.content.contains("running warm"))
        XCTAssertTrue(large.content.contains("W of power"))
        XCTAssertFalse(large.content.contains("unavailable"))

        let ordinary = try await service.generateDeviceSummary(forDevice: "192.0.2.3")
        XCTAssertTrue(ordinary.content.contains("65°C"))
        XCTAssertTrue(ordinary.content.contains("15W"))
    }

    func testLegacyFleetFormatterHandlesLargeAndUnavailableTemperatures() throws {
        let large = try XCTUnwrap(
            AISummaryFormatter.fleetSummary(from: [
                DeviceMetrics(hashrate: 500, temperature: .greatestFiniteMagnitude, power: 15)
            ])
        )
        XCTAssertTrue(large.content.contains("above 75°C"))
        let invalid = try XCTUnwrap(
            AISummaryFormatter.fleetSummary(from: [
                DeviceMetrics(hashrate: 500, temperature: .infinity, power: 15)
            ])
        )
        XCTAssertTrue(invalid.content.contains("temperature unavailable"))
        XCTAssertFalse(invalid.content.contains("0°C"))
    }
}
