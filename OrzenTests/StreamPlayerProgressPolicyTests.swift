import XCTest
@testable import Orzen

final class StreamPlayerProgressPolicyTests: XCTestCase {
    func testMovieRequiresTwentyMinutesBeforeItCanComplete() {
        XCTAssertFalse(StreamPlayerProgressPolicy.canComplete(duration: 1_199, contentType: .movie))
        XCTAssertTrue(StreamPlayerProgressPolicy.canComplete(duration: 1_200, contentType: .movie))
    }

    func testEpisodeRequiresFiveMinutesBeforeItCanComplete() {
        XCTAssertFalse(StreamPlayerProgressPolicy.canComplete(duration: 299, contentType: .series))
        XCTAssertTrue(StreamPlayerProgressPolicy.canComplete(duration: 300, contentType: .series))
    }

    func testNonFiniteDurationCannotComplete() {
        XCTAssertFalse(StreamPlayerProgressPolicy.canComplete(duration: .infinity, contentType: .movie))
        XCTAssertFalse(StreamPlayerProgressPolicy.canComplete(duration: .nan, contentType: .series))
    }

    func testPlaybackEndUsesOnePointTwentyFiveSecondTolerance() {
        XCTAssertFalse(StreamPlayerProgressPolicy.hasReachedPlaybackEnd(currentTime: 98.74, duration: 100))
        XCTAssertTrue(StreamPlayerProgressPolicy.hasReachedPlaybackEnd(currentTime: 98.75, duration: 100))
        XCTAssertTrue(StreamPlayerProgressPolicy.hasReachedPlaybackEnd(currentTime: 101, duration: 100))
    }

    func testInvalidTimelineNeverReachesPlaybackEnd() {
        XCTAssertFalse(StreamPlayerProgressPolicy.hasReachedPlaybackEnd(currentTime: 0, duration: 0))
        XCTAssertFalse(StreamPlayerProgressPolicy.hasReachedPlaybackEnd(currentTime: .nan, duration: 100))
        XCTAssertFalse(StreamPlayerProgressPolicy.hasReachedPlaybackEnd(currentTime: 10, duration: .infinity))
    }

    func testResumeAppliesOnlyOnceWithAnActiveEngineAndUsableDuration() {
        XCTAssertEqual(
            StreamPlayerProgressPolicy.resumePositionToApply(
                hasAppliedSavedProgress: false,
                pendingResumePosition: 42,
                hasActivePlaybackEngine: true,
                duration: 100
            ),
            42
        )
        XCTAssertNil(
            StreamPlayerProgressPolicy.resumePositionToApply(
                hasAppliedSavedProgress: true,
                pendingResumePosition: 42,
                hasActivePlaybackEngine: true,
                duration: 100
            )
        )
        XCTAssertNil(
            StreamPlayerProgressPolicy.resumePositionToApply(
                hasAppliedSavedProgress: false,
                pendingResumePosition: 42,
                hasActivePlaybackEngine: false,
                duration: 100
            )
        )
    }

    func testResumeIsSkippedWithinLastFiveSeconds() {
        XCTAssertNil(
            StreamPlayerProgressPolicy.resumePositionToApply(
                hasAppliedSavedProgress: false,
                pendingResumePosition: 95,
                hasActivePlaybackEngine: true,
                duration: 100
            )
        )
        XCTAssertEqual(
            StreamPlayerProgressPolicy.resumePositionToApply(
                hasAppliedSavedProgress: false,
                pendingResumePosition: 94.99,
                hasActivePlaybackEngine: true,
                duration: 100
            ),
            94.99
        )
    }

    func testCompletedLongContentIsCompletedInsteadOfSaved() {
        XCTAssertEqual(
            action(duration: 7_200, contentType: .movie, storeComplete: true),
            .complete
        )
        XCTAssertEqual(
            action(duration: 1_800, contentType: .series, storeComplete: true),
            .complete
        )
    }

    func testShortContentIsClearedEvenWhenStoreDoesNotConsiderItComplete() {
        XCTAssertEqual(
            action(duration: 600, contentType: .movie, storeComplete: false),
            .clear
        )
        XCTAssertEqual(
            action(duration: 120, contentType: .series, storeComplete: false),
            .clear
        )
    }

    func testProgressIsIgnoredWithoutHealthyActivePlayback() {
        XCTAssertEqual(action(hasActiveEngine: false), .ignore)
        XCTAssertEqual(action(hasPlaybackError: true), .ignore)
        XCTAssertEqual(action(hasCompleted: true), .ignore)
        XCTAssertEqual(action(currentTime: .nan), .ignore)
    }

    func testProgressWaitsUntilPendingResumeWasApplied() {
        XCTAssertEqual(
            action(
                currentTime: 20,
                duration: 7_200,
                pendingResumePosition: 120,
                hasAppliedSavedProgress: false
            ),
            .ignore
        )
    }

    func testProgressIsThrottledToOneSecondUnlessForced() {
        XCTAssertEqual(action(currentTime: 10.5, lastSavedPosition: 10), .ignore)
        XCTAssertEqual(action(currentTime: 10.5, lastSavedPosition: 10, force: true), .save)
        XCTAssertEqual(action(currentTime: 11, lastSavedPosition: 10), .save)
    }

    private func action(
        hasCompleted: Bool = false,
        hasActiveEngine: Bool = true,
        hasPlaybackError: Bool = false,
        currentTime: Double = 600,
        duration: Double = 7_200,
        contentType: CinemetaType = .movie,
        storeComplete: Bool = false,
        pendingResumePosition: Double? = nil,
        hasAppliedSavedProgress: Bool = true,
        lastSavedPosition: Double = 0,
        force: Bool = false
    ) -> StreamPlayerProgressAction {
        StreamPlayerProgressPolicy.action(
            hasCompletedCurrentContent: hasCompleted,
            hasActivePlaybackEngine: hasActiveEngine,
            hasPlaybackError: hasPlaybackError,
            currentTime: currentTime,
            duration: duration,
            contentType: contentType,
            progressStoreConsidersComplete: storeComplete,
            pendingResumePosition: pendingResumePosition,
            hasAppliedSavedProgress: hasAppliedSavedProgress,
            lastSavedProgressPosition: lastSavedPosition,
            force: force
        )
    }
}
