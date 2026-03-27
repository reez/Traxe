import Foundation
import XCTest

@testable import Traxe

final class CachedDeviceMetricsCompatibilityTests: XCTestCase {
    func testAppCachePayloadDecodesWithWidgetAndWatchSchemas() throws {
        let metrics = DeviceMetrics(
            hashrate: 1_250,
            temperature: 62,
            power: 18,
            bestDifficulty: 7,
            poolURL: "stratum+tcp://pool.example.com",
            hostname: "Miner A",
            blockHeight: 100,
            networkDifficulty: 2_500
        )
        let payload = [
            "192.168.1.10": CachedDeviceMetrics(from: metrics)
        ]

        let data = try makeEncoder().encode(payload)

        let widgetDecoded = try makeDecoder().decode(
            [String: WidgetCachedDeviceMetrics].self,
            from: data
        )
        let watchDecoded = try makeDecoder().decode(
            [String: WatchCachedDeviceMetrics].self,
            from: data
        )

        XCTAssertEqual(widgetDecoded["192.168.1.10"]?.hashrate, 1_250)
        XCTAssertEqual(widgetDecoded["192.168.1.10"]?.hostname, "Miner A")
        XCTAssertEqual(widgetDecoded["192.168.1.10"]?.temperature, 62)

        XCTAssertEqual(watchDecoded["192.168.1.10"]?.hashrate, 1_250)
        XCTAssertEqual(watchDecoded["192.168.1.10"]?.hostname, "Miner A")
        XCTAssertEqual(watchDecoded["192.168.1.10"]?.temperature, 62)
    }

    func testWidgetPayloadDecodesWithAppSchema() throws {
        let payload = [
            "192.168.1.10": WidgetCachedDeviceMetrics(
                hashrate: 980,
                power: 15,
                bestDifficulty: 4,
                hostname: "Widget Miner",
                poolURL: "stratum+tcp://widget.pool",
                temperature: 58,
                lastUpdated: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ]

        let data = try makeEncoder().encode(payload)
        let decoded = try makeDecoder().decode([String: CachedDeviceMetrics].self, from: data)

        XCTAssertEqual(decoded["192.168.1.10"]?.hashrate, 980)
        XCTAssertEqual(decoded["192.168.1.10"]?.hostname, "Widget Miner")
        XCTAssertEqual(decoded["192.168.1.10"]?.temperature, 58)
        XCTAssertNil(decoded["192.168.1.10"]?.blockHeight)
        XCTAssertNil(decoded["192.168.1.10"]?.networkDifficulty)
    }

    func testWatchPayloadDecodesWithAppSchema() throws {
        let payload = [
            "192.168.1.11": WatchCachedDeviceMetrics(
                hashrate: 640,
                power: 12,
                bestDifficulty: 3,
                hostname: "Watch Miner",
                poolURL: "stratum+tcp://watch.pool",
                temperature: 54,
                lastUpdated: Date(timeIntervalSince1970: 1_700_000_100)
            )
        ]

        let data = try makeEncoder().encode(payload)
        let decoded = try makeDecoder().decode([String: CachedDeviceMetrics].self, from: data)

        XCTAssertEqual(decoded["192.168.1.11"]?.hashrate, 640)
        XCTAssertEqual(decoded["192.168.1.11"]?.hostname, "Watch Miner")
        XCTAssertEqual(decoded["192.168.1.11"]?.temperature, 54)
        XCTAssertNil(decoded["192.168.1.11"]?.blockHeight)
        XCTAssertNil(decoded["192.168.1.11"]?.networkDifficulty)
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct WidgetCachedDeviceMetrics: Codable {
    var hashrate: Double
    var power: Double?
    var bestDifficulty: Double?
    var hostname: String?
    var poolURL: String?
    var temperature: Double?
    var lastUpdated: Date
}

private struct WatchCachedDeviceMetrics: Codable {
    var hashrate: Double
    var power: Double?
    var bestDifficulty: Double?
    var hostname: String?
    var poolURL: String?
    var temperature: Double?
    var lastUpdated: Date
}
