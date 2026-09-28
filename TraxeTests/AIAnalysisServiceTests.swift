import Foundation
import XCTest

@testable import Traxe

@MainActor
final class AIAnalysisServiceTests: XCTestCase {
    func testHistoricalSummaryUsesRecordedSamplesWithoutAddingACalendarDate() async throws {
        final class TelemetryStub: URLProtocol {
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
                else {
                    client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                    return
                }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(#"{"hashRate":0}"#.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }
            override func stopLoading() {}
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TelemetryStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = AIAnalysisService(networkService: NetworkService(session: session))
        let start = Date(timeIntervalSince1970: 1_600_000_000)
        // Unsorted, sparse, old samples: a zero contributes to the mean, and the span
        // describes recorded history rather than continuous uptime or a window ending now.
        let history = [
            HistoricalDataPoint(
                timestamp: start.addingTimeInterval(13 * 86_400),
                hashrate: 7_400,
                temperature: 60
            ),
            HistoricalDataPoint(timestamp: start, hashrate: 0, temperature: 30),
        ]
        let summary = try await service.generateDeviceSummary(
            forDevice: "192.0.2.10",
            withHistoricalData: history
        )

        let averageText = 3.7.formatted(.number.precision(.fractionLength(1)))
        XCTAssertEqual(
            summary.content,
            "Averaged \(averageText) TH/s across samples spanning 13 days."
        )
    }

    func testHistoricalSummaryPreservesMiningLuckAndDurationUnits() async throws {
        final class TelemetryStub: URLProtocol {
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
                else {
                    client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                    return
                }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(
                    self,
                    didLoad: Data(#"{"hashRate":1000,"networkDifficulty":100000000000000}"#.utf8)
                )
                client?.urlProtocolDidFinishLoading(self)
            }
            override func stopLoading() {}
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TelemetryStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = AIAnalysisService(networkService: NetworkService(session: session))
        let start = Date(timeIntervalSince1970: 1_600_000_000)
        let cases: [(TimeInterval, String)] = [
            (600, "10 minutes"), (3_600, "1 hour"), (86_400, "1 day"),
        ]
        for (span, expectedDuration) in cases {
            let history = [
                HistoricalDataPoint(timestamp: start, hashrate: 1_000, temperature: 60),
                HistoricalDataPoint(
                    timestamp: start.addingTimeInterval(span),
                    hashrate: 1_000,
                    temperature: 60
                ),
            ]
            let summary = try await service.generateDeviceSummary(
                forDevice: "192.0.2.10",
                withHistoricalData: history
            )
            let averageText = 1.0.formatted(.number.precision(.fractionLength(1)))
            let expectedPrefix =
                "Averaged \(averageText) TH/s across samples spanning \(expectedDuration). "
            XCTAssertTrue(summary.content.hasPrefix(expectedPrefix))
            XCTAssertTrue(summary.content.dropFirst(expectedPrefix.count).contains("solo odds"))
        }
    }
}
