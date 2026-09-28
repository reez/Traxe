import Foundation
import XCTest

@testable import Traxe

final class NetworkServiceTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        URLProtocolStub.capturedRequest = nil
        URLProtocolStub.capturedBodyData = nil
        super.tearDown()
    }

    func testUpdateSystemSettingsSendsStratumV2Fields() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let service = NetworkService(session: session)

        URLProtocolStub.requestHandler = { request in
            URLProtocolStub.capturedRequest = request
            URLProtocolStub.capturedBodyData = Self.bodyData(from: request)
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (try XCTUnwrap(response), Data())
        }

        try await service.updateSystemSettings(
            stratumProtocol: "SV2",
            fallbackStratumProtocol: "SV1",
            stratumV2ChannelType: "extended",
            fallbackStratumV2ChannelType: "standard",
            stratumV2AuthorityPubkey: "",
            fallbackStratumV2AuthorityPubkey: "9c4zpyJ2ndm4e8sP2uNc1VNCGxYjqaxWS6wUCjk8zFj6njFquH6",
            ipAddressOverride: "192.0.2.10"
        )

        let capturedRequest = try XCTUnwrap(URLProtocolStub.capturedRequest)
        XCTAssertEqual(capturedRequest.httpMethod, "PATCH")
        XCTAssertEqual(capturedRequest.url?.absoluteString, "http://192.0.2.10/api/system")

        let bodyData = try XCTUnwrap(URLProtocolStub.capturedBodyData)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )
        XCTAssertEqual(body["stratumProtocol"] as? String, "SV2")
        XCTAssertEqual(body["fallbackStratumProtocol"] as? String, "SV1")
        XCTAssertEqual(body["stratumV2ChannelType"] as? String, "extended")
        XCTAssertEqual(body["fallbackStratumV2ChannelType"] as? String, "standard")
        XCTAssertEqual(body["stratumV2AuthorityPubkey"] as? String, "")
        XCTAssertEqual(
            body["fallbackStratumV2AuthorityPubkey"] as? String,
            "9c4zpyJ2ndm4e8sP2uNc1VNCGxYjqaxWS6wUCjk8zFj6njFquH6"
        )
    }

    func testUpdatePoolSettingsSendsUseFallbackStratumAsANumberOnlyWhenGiven() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let service = NetworkService(session: session)

        URLProtocolStub.requestHandler = { request in
            URLProtocolStub.capturedRequest = request
            URLProtocolStub.capturedBodyData = Self.bodyData(from: request)
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (try XCTUnwrap(response), Data())
        }
        let pool = MinerPoolDTO(
            properties: ["id": .int(2), "stratumURL": .string("public-pool.io")]
        )

        try await service.updatePoolSettings(
            pools: [pool],
            useFallbackStratum: true,
            ipAddressOverride: "192.0.2.10"
        )

        let capturedRequest = try XCTUnwrap(URLProtocolStub.capturedRequest)
        XCTAssertEqual(capturedRequest.httpMethod, "PATCH")
        XCTAssertEqual(capturedRequest.url?.absoluteString, "http://192.0.2.10/api/system")
        var body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(URLProtocolStub.capturedBodyData))
                as? [String: Any]
        )
        XCTAssertEqual((body["pools"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(body["useFallbackStratum"] as? Int, 1)

        try await service.updatePoolSettings(pools: [pool], ipAddressOverride: "192.0.2.10")

        body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(URLProtocolStub.capturedBodyData))
                as? [String: Any]
        )
        XCTAssertEqual((body["pools"] as? [[String: Any]])?.count, 1)
        XCTAssertNil(body["useFallbackStratum"], "An unchanged active pool must not be sent")

        try await service.updatePoolSettings(
            pools: [],
            useFallbackStratum: false,
            ipAddressOverride: "192.0.2.10"
        )

        body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(URLProtocolStub.capturedBodyData))
                as? [String: Any]
        )
        XCTAssertNil(body["pools"], "No pool edits means no pools array")
        XCTAssertEqual(body["useFallbackStratum"] as? Int, 0)
    }

    func testFetchMinerTelemetryDecodesPayloadThatFullSystemInfoRejects() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let service = NetworkService(session: session)
        let payload = try Self.fixtureData(named: "poisoned-optional-settings-system-info.json")

        URLProtocolStub.requestHandler = { request in
            URLProtocolStub.capturedRequest = request
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (try XCTUnwrap(response), payload)
        }

        do {
            _ = try await service.fetchSystemInfo(ipAddressOverride: "192.0.2.10")
            XCTFail("SystemInfoDTO should reject the poisoned settings field")
        } catch NetworkError.decodingError {
        } catch {
            XCTFail("Expected decodingError, got \(error)")
        }

        let telemetry = try await service.fetchMinerTelemetry(ipAddressOverride: "192.0.2.10")

        XCTAssertEqual(
            URLProtocolStub.capturedRequest?.url?.absoluteString,
            "http://192.0.2.10/api/system/info"
        )
        XCTAssertEqual(telemetry.hostname, "future-miner")
        XCTAssertEqual(telemetry.hashrate, 777.0)
        XCTAssertEqual(DeviceMetrics(from: telemetry).temperature, 49.0)
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let httpBody = request.httpBody {
            return httpBody
        }

        guard let bodyStream = request.httpBodyStream else { return nil }
        bodyStream.open()
        defer { bodyStream.close() }

        var data = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while bodyStream.hasBytesAvailable {
            let readCount = bodyStream.read(buffer, maxLength: bufferSize)
            guard readCount > 0 else { break }
            data.append(buffer, count: readCount)
        }

        return data
    }

    private static func fixtureData(named filename: String) throws -> Data {
        let testFile = URL(fileURLWithPath: #filePath)
        let fixtureURL = testFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Firmware")
            .appendingPathComponent(filename)
        return try Data(contentsOf: fixtureURL)
    }
}

private final class URLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var requestHandler:
        ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var capturedRequest: URLRequest?
    nonisolated(unsafe) static var capturedBodyData: Data?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NetworkError.unknown)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
