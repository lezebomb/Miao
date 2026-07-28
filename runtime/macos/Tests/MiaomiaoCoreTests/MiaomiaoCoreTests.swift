import Foundation
import XCTest
@testable import MiaomiaoCore

final class MiaomiaoCoreTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testRepositoryJSONAndEveryFrameLoad() throws {
        let resources = try RuntimeResources(root: repositoryRoot)
        XCTAssertFalse(resources.behavior.actions.isEmpty)
        XCTAssertGreaterThan(resources.configuration.globalDurationScale, 0)
        XCTAssertGreaterThan(resources.configuration.windowScale, 0)

        for action in resources.behavior.actions.values {
            for frame in action.frames {
                let data = try Data(contentsOf: resources.frameURL(relativePath: frame))
                XCTAssertGreaterThan(data.count, 8)
                XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
            }
        }
    }

    func testConfiguredPlaybackRepeatsAndStops() throws {
        let resources = try RuntimeResources(root: repositoryRoot)
        for action in resources.behavior.actions.values where !action.loop {
            var cursor = PlaybackCursor()
            let expectedFrames = action.frames.count * (action.repeatCount ?? 1)
            var visitedFrames = 1
            while cursor.advance(
                frameCount: action.frames.count,
                repeatCount: action.repeatCount ?? 1,
                loops: false
            ) {
                visitedFrames += 1
            }
            XCTAssertEqual(visitedFrames, expectedFrames)
        }
    }

    func testDragClassificationUsesConfiguredThresholds() throws {
        let config = try RuntimeResources(root: repositoryRoot).configuration.drag
        XCTAssertEqual(
            InteractionLogic.dragDirection(
                deltaX: -(config.horizontalThresholdPx + 1),
                deltaY: 0,
                threshold: config.horizontalThresholdPx,
                dominanceRatio: config.horizontalDominanceRatio
            ),
            .left
        )
        XCTAssertEqual(
            InteractionLogic.dragDirection(
                deltaX: config.horizontalThresholdPx + 1,
                deltaY: 0,
                threshold: config.horizontalThresholdPx,
                dominanceRatio: config.horizontalDominanceRatio
            ),
            .right
        )
        XCTAssertEqual(
            InteractionLogic.dragDirection(
                deltaX: config.horizontalThresholdPx + 1,
                deltaY: config.horizontalThresholdPx + 1,
                threshold: config.horizontalThresholdPx,
                dominanceRatio: config.horizontalDominanceRatio
            ),
            .none
        )
    }

    func testWeightedChoiceHonorsJSONWeights() throws {
        let event = try RuntimeResources(root: repositoryRoot).behavior.events.petOrHover
        XCTAssertEqual(
            WeightedChoice.choose(names: event.random, weights: event.weights, unitRandom: 0),
            event.random.first
        )
        XCTAssertEqual(
            WeightedChoice.choose(names: event.random, weights: event.weights, unitRandom: 0.999),
            event.random.last
        )
    }
}
