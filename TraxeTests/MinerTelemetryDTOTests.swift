import XCTest

@testable import Traxe

final class MinerTelemetryDTOTests: XCTestCase {
    func testDecodesFirmwareTelemetryFixtures() throws {
        let expectations: [(filename: String, hashrate: Double, hostname: String)] = [
            ("esp-miner-string-system-info.json", 565.0, "bitaxe-601"),
            ("nerdqaxe-v1-0-35-system-info.json", 4200.0, "nerdqaxe-plus"),
            ("nerdqaxe-v1-0-37-2-lts-system-info.json", 1234.0, "nerdqaxe-plus"),
        ]

        for expectation in expectations {
            let telemetry = try decodeTelemetryFixture(named: expectation.filename)

            XCTAssertTrue(
                telemetry.isCompatibleMiner,
                "\(expectation.filename) should be accepted as a supported miner"
            )
            XCTAssertEqual(telemetry.hostname, expectation.hostname)
            XCTAssertEqual(telemetry.hashrate ?? 0, expectation.hashrate, accuracy: 0.001)
            XCTAssertNotEqual(DeviceMetrics(from: telemetry).hashrate, 0)
        }
    }

    func testTelemetryDecodeSurvivesOptionalSettingsFieldShapeChanges() throws {
        let data = try fixtureData(named: "poisoned-optional-settings-system-info.json")

        XCTAssertThrowsError(try JSONDecoder().decode(SystemInfoDTO.self, from: data))

        let telemetry = try JSONDecoder().decode(MinerTelemetryDTO.self, from: data)
        let metrics = DeviceMetrics(from: telemetry)

        XCTAssertTrue(telemetry.isCompatibleMiner)
        XCTAssertEqual(telemetry.hostname, "future-miner")
        XCTAssertEqual(telemetry.version, "future-fw")
        XCTAssertEqual(metrics.hashrate, 777.0, accuracy: 0.001)
        XCTAssertEqual(metrics.temperature, 49.0, accuracy: 0.001)
        XCTAssertEqual(metrics.power, 88.0, accuracy: 0.001)
        XCTAssertEqual(metrics.fanSpeedPercent, 64)
    }

    func testCompatibilityRequiresRealMinerIdentityFields() throws {
        let emptyTelemetry = try JSONDecoder().decode(MinerTelemetryDTO.self, from: Data("{}".utf8))

        XCTAssertEqual(emptyTelemetry.hostname, "Unknown Miner")
        XCTAssertFalse(emptyTelemetry.isCompatibleMiner)
        XCTAssertEqual(emptyTelemetry.deviceType, .unknown)

        let fallbackOnlyPayload = """
            {
                "hostname": "Unknown Miner",
                "version": "Unknown",
                "ASICModel": "Unknown"
            }
            """
        let fallbackOnlyTelemetry = try JSONDecoder().decode(
            MinerTelemetryDTO.self,
            from: Data(fallbackOnlyPayload.utf8)
        )

        XCTAssertFalse(fallbackOnlyTelemetry.isCompatibleMiner)
        XCTAssertEqual(fallbackOnlyTelemetry.deviceType, .unknown)
    }

    func testNewNerdQaxeTelemetryIgnoresSettingsOnlySchemaChanges() throws {
        let telemetry = try decodeTelemetryFixture(named: "nerdqaxe-v1-0-37-2-lts-system-info.json")

        XCTAssertEqual(telemetry.deviceType, .nerdqaxe)
        XCTAssertEqual(telemetry.version, "V1.0.37.2-LTS")
        XCTAssertEqual(telemetry.hashrate, 1234.0)
        XCTAssertEqual(telemetry.bestDiff, "12345")
        XCTAssertEqual(
            telemetry.poolURL,
            "new.nerd.pool.example (50%) • new.nerd.backup.example (50%)"
        )
    }

    func testIntegerTelemetryRejectsUnrepresentableNumbers() throws {
        let values = [
            "1e100", "-1e100", "9223372036854775808", "-9223372036854777856",
            "\"NaN\"", "\"Infinity\"", "\"-Infinity\"",
        ]
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )

        for value in values {
            let payload = """
                {"hostname": "bitaxe", "frequency": \(value), "fanspeed": \(value), "uptimeSeconds": \(value)}
                """
            let telemetry = try decoder.decode(MinerTelemetryDTO.self, from: Data(payload.utf8))

            XCTAssertNil(telemetry.frequency, value)
            XCTAssertNil(telemetry.fanspeed, value)
            XCTAssertNil(telemetry.uptimeSeconds, value)
            XCTAssertTrue(telemetry.isCompatibleMiner)
        }
    }

    func testIntegerTelemetryPreservesBoundsAndTruncatesFractionsTowardZero() throws {
        let payload = """
            {
                "sharesAccepted": \(Int.max),
                "sharesRejected": \(Int.min),
                "fanspeed": 64.9,
                "wifiRSSI": -42.9,
                "frequency": " 600 "
            }
            """
        let telemetry = try JSONDecoder().decode(MinerTelemetryDTO.self, from: Data(payload.utf8))

        XCTAssertEqual(telemetry.sharesAccepted, Int.max)
        XCTAssertEqual(telemetry.sharesRejected, Int.min)
        XCTAssertEqual(telemetry.fanspeed, 64)
        XCTAssertEqual(telemetry.wifiRSSI, -42)
        XCTAssertEqual(telemetry.frequency, 600)
    }

    private func decodeTelemetryFixture(named filename: String) throws -> MinerTelemetryDTO {
        let data = try fixtureData(named: filename)
        return try JSONDecoder().decode(MinerTelemetryDTO.self, from: data)
    }

    private func fixtureData(named filename: String) throws -> Data {
        let testFile = URL(fileURLWithPath: #filePath)
        let fixtureURL = testFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent(filename)
        return try Data(contentsOf: fixtureURL)
    }
}
