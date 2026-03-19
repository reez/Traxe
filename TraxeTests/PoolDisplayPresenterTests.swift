import XCTest

@testable import Traxe

final class PoolDisplayPresenterTests: XCTestCase {
    func testMakeRowsSplitsPoolsAndResolvesKnownLogos() {
        let rows = PoolDisplayPresenter.makeRows(
            from: "mine.ocean.xyz (65%) • publicpool.io (35%)"
        )

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].text, "mine.ocean.xyz (65%)")
        XCTAssertEqual(rows[0].logoName, "ocean")
        XCTAssertEqual(rows[1].text, "publicpool.io (35%)")
        XCTAssertEqual(rows[1].logoName, "publicpool")
    }

    func testMakeRowsReturnsEmptyForNilOrBlankSegments() {
        XCTAssertTrue(PoolDisplayPresenter.makeRows(from: nil).isEmpty)
        XCTAssertTrue(PoolDisplayPresenter.makeRows(from: " • ").isEmpty)
    }
}
