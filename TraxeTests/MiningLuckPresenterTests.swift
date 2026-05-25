import XCTest

@testable import Traxe

final class MiningLuckPresenterTests: XCTestCase {
    func testMakeSnapshotComputesSoloMiningProbability() {
        let metrics = DeviceMetrics(
            hashrate: 1_000,
            networkDifficulty: 100_000_000_000_000
        )

        let snapshot = MiningLuckPresenter.makeSnapshot(from: metrics)

        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.expectedSecondsToBlock ?? 0, 429_496_729_600, accuracy: 1)
        XCTAssertEqual(snapshot?.dailyBlockProbability ?? 0, 0.000000201, accuracy: 0.000000001)
    }

    func testMakeSnapshotRequiresFinitePositiveHashrateAndNetworkDifficulty() {
        XCTAssertNil(
            MiningLuckPresenter.makeSnapshot(
                from: DeviceMetrics(hashrate: 0, networkDifficulty: 1)
            )
        )
        XCTAssertNil(
            MiningLuckPresenter.makeSnapshot(
                from: DeviceMetrics(hashrate: .infinity, networkDifficulty: 1)
            )
        )
        XCTAssertNil(
            MiningLuckPresenter.makeSnapshot(
                from: DeviceMetrics(hashrate: 1, networkDifficulty: nil)
            )
        )
        XCTAssertNil(
            MiningLuckPresenter.makeSnapshot(
                from: DeviceMetrics(hashrate: 1, networkDifficulty: 0)
            )
        )
        XCTAssertNil(
            MiningLuckPresenter.makeSnapshot(
                from: DeviceMetrics(hashrate: 1, networkDifficulty: .infinity)
            )
        )
    }

    func testMakeSummarySentenceUsesLuckValues() {
        let metrics = DeviceMetrics(
            hashrate: 1_000,
            networkDifficulty: 100_000_000_000_000
        )

        let sentence = MiningLuckPresenter.makeSummarySentence(from: metrics)

        XCTAssertEqual(
            sentence,
            "This miner's solo odds to hit a block are 1 in 5M today (13.6K yr expected)."
        )
    }
}
