import XCTest

@testable import Traxe

final class PoolHostPresenterTests: XCTestCase {
    func testMetadataNormalizesKnownHostWithTrailingPercentSuffix() {
        let metadata = PoolHostPresenter.metadata(from: "mine.ocean.xyz (65%)")

        XCTAssertEqual(
            metadata,
            PoolHostMetadata(
                normalizedHost: "mine.ocean.xyz",
                displayName: "Ocean",
                logoName: "ocean",
                poolSlug: "ocean"
            )
        )
    }

    func testMetadataParsesSchemeAndPortForKnownPools() {
        let metadata = PoolHostPresenter.metadata(from: "stratum+tcp://publicpool.io:21496")

        XCTAssertEqual(
            metadata,
            PoolHostMetadata(
                normalizedHost: "publicpool.io",
                displayName: "Public Pool",
                logoName: "publicpool",
                poolSlug: "publicpool"
            )
        )
    }

    func testMetadataLeavesUnknownPoolLogoAndSlugNil() {
        let metadata = PoolHostPresenter.metadata(from: "www.unknownpool.example:4444/path")

        XCTAssertEqual(
            metadata,
            PoolHostMetadata(
                normalizedHost: "www.unknownpool.example",
                displayName: "unknownpool.example",
                logoName: nil,
                poolSlug: nil
            )
        )
    }
}
