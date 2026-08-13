import XCTest
@testable import Orzen

final class StreamPlayerPlaybackPolicyTests: XCTestCase {
    func testPictureInPictureSessionRoutesStartStopAndDetach() {
        let session = PictureInPictureSession()
        let registrationID = UUID()
        var startCount = 0
        var stopCount = 0

        session.attach(
            registrationID: registrationID,
            isPossible: true,
            isActive: false,
            start: { startCount += 1 },
            stop: { stopCount += 1 }
        )

        XCTAssertTrue(session.isAvailable)
        session.toggle()
        XCTAssertEqual(startCount, 1)

        session.update(
            registrationID: registrationID,
            isPossible: true,
            isActive: true
        )
        session.toggle()
        XCTAssertEqual(stopCount, 1)

        session.detach(registrationID: registrationID)
        XCTAssertFalse(session.isAvailable)
        XCTAssertFalse(session.isActive)
    }

    func testNowPlayingMetadataUsesEpisodeArtworkAndSeriesName() {
        let item = CatalogItem(
            id: "series-1",
            title: "Test Series",
            description: "Description",
            posterURL: URL(string: "https://example.com/poster.jpg"),
            backgroundURL: URL(string: "https://example.com/background.jpg"),
            cinemetaType: .series
        )
        let episode = CatalogEpisode(
            id: "episode-1",
            title: "Pilot",
            description: nil,
            thumbnailURL: URL(string: "https://example.com/episode.jpg"),
            runtime: nil,
            released: nil,
            season: 1,
            episode: 1
        )
        let request = TestFixtures.request(
            item: item,
            episode: episode,
            contentID: episode.id,
            contentType: .series
        )

        let metadata = StreamNowPlayingMetadata(request: request)

        XCTAssertEqual(metadata.title, episode.playbackTitle)
        XCTAssertEqual(metadata.subtitle, item.title)
        XCTAssertEqual(metadata.artworkURL, episode.thumbnailURL)
        XCTAssertEqual(metadata.contentID, episode.id)
    }

    func testNowPlayingMetadataAvoidsDuplicateMovieSubtitle() {
        let request = TestFixtures.request()
        let metadata = StreamNowPlayingMetadata(request: request)

        XCTAssertEqual(metadata.title, request.title)
        XCTAssertNil(metadata.subtitle)
        XCTAssertEqual(metadata.contentID, request.contentID)
    }

    func testInvalidSourceFailsBeforeSelectingAnEngine() {
        let source = TestFixtures.source(url: URL(string: "file:///tmp/video.mp4"))

        guard case .failure(let message) = StreamPlayerPlaybackPolicy.initialDecision(
            for: source,
            platform: .macOS,
            isVLCAvailable: false
        ) else {
            return XCTFail("Expected an invalid URL failure")
        }

        XCTAssertTrue(message.contains("unsupported URL scheme"))
    }

    func testTorrentOnlySourceFailsWithActionableMessage() {
        let source = TestFixtures.source(url: nil, torrentInfoHash: "abc123")

        guard case .failure(let message) = StreamPlayerPlaybackPolicy.initialDecision(
            for: source,
            platform: .iOS,
            isVLCAvailable: true
        ) else {
            return XCTFail("Expected a torrent-only failure")
        }

        XCTAssertTrue(message.contains("BitTorrent"))
    }

    func testMacUsesMPVForDirectSources() {
        let source = TestFixtures.source(url: URL(string: "https://example.com/video.mkv"))

        XCTAssertEqual(
            StreamPlayerPlaybackPolicy.initialDecision(
                for: source,
                platform: .macOS,
                isVLCAvailable: false
            ),
            .play(source.playbackURL!, with: .mpv)
        )
    }

    func testIOSPrefersVLCWhenAvailable() {
        let source = TestFixtures.source()

        XCTAssertEqual(
            StreamPlayerPlaybackPolicy.initialDecision(
                for: source,
                platform: .iOS,
                isVLCAvailable: true
            ),
            .play(source.playbackURL!, with: .vlc)
        )
    }

    func testIOSFallsBackToNativeWhenVLCIsUnavailable() {
        let source = TestFixtures.source()

        XCTAssertEqual(
            StreamPlayerPlaybackPolicy.initialDecision(
                for: source,
                platform: .iOS,
                isVLCAvailable: false
            ),
            .play(source.playbackURL!, with: .native)
        )
    }

    func testForegroundRecoveryResumesPlaybackThatWasPlayingBeforeBackground() {
        XCTAssertEqual(
            StreamPlayerLifecyclePolicy.foregroundAction(
                for: .vlc,
                wasPausedBeforeBackground: false,
                hasEnteredBackground: true,
                isPictureInPictureActive: false
            ),
            .recoverVideoOutput(shouldResume: true, requiresTrackReset: false)
        )
    }

    func testForegroundRecoveryPreservesPausedPlayback() {
        XCTAssertEqual(
            StreamPlayerLifecyclePolicy.foregroundAction(
                for: .vlc,
                wasPausedBeforeBackground: true,
                hasEnteredBackground: true,
                isPictureInPictureActive: false
            ),
            .recoverVideoOutput(shouldResume: false, requiresTrackReset: true)
        )
    }

    func testForegroundRecoveryDoesNotDisruptPictureInPicture() {
        XCTAssertEqual(
            StreamPlayerLifecyclePolicy.foregroundAction(
                for: .vlc,
                wasPausedBeforeBackground: false,
                hasEnteredBackground: true,
                isPictureInPictureActive: true
            ),
            .none
        )
    }

    func testForegroundRecoveryRequiresCapturedPlaybackState() {
        XCTAssertEqual(
            StreamPlayerLifecyclePolicy.foregroundAction(
                for: .vlc,
                wasPausedBeforeBackground: nil,
                hasEnteredBackground: true,
                isPictureInPictureActive: false
            ),
            .none
        )
    }

    func testCancelledHomeGestureDoesNotRecoverVideoOutput() {
        XCTAssertEqual(
            StreamPlayerLifecyclePolicy.foregroundAction(
                for: .vlc,
                wasPausedBeforeBackground: false,
                hasEnteredBackground: false,
                isPictureInPictureActive: false
            ),
            .none
        )
    }

    func testFallbackExcludesCurrentPreviouslyAttemptedAndUnsupportedSources() {
        let current = TestFixtures.source(id: "current", url: URL(string: "https://example.com/current.mp4"))
        let attempted = TestFixtures.source(id: "attempted", url: URL(string: "https://example.com/attempted.m3u8"))
        let unsupported = TestFixtures.source(id: "unsupported", url: URL(string: "https://example.com/video.mkv"))
        let likely = TestFixtures.source(id: "likely", title: "A MP4", url: URL(string: "https://example.com/video.mp4"))
        let supported = TestFixtures.source(id: "supported", title: "Z HLS", url: URL(string: "https://example.com/video.m3u8"))

        let selection = StreamPlayerPlaybackPolicy.fallbackSelection(
            currentSource: current,
            previouslyAttemptedSourceIDs: [attempted.id],
            candidates: [current, attempted, unsupported, likely, supported]
        )

        XCTAssertEqual(selection?.source, supported)
        XCTAssertEqual(selection?.attemptedSourceIDs, [current.id, attempted.id])
    }

    func testFallbackReturnsNilWhenNoEligibleSourceExists() {
        let current = TestFixtures.source(id: "current")
        let unsupported = TestFixtures.source(id: "unsupported", url: URL(string: "https://example.com/video.mkv"))

        XCTAssertNil(
            StreamPlayerPlaybackPolicy.fallbackSelection(
                currentSource: current,
                previouslyAttemptedSourceIDs: [],
                candidates: [current, unsupported]
            )
        )
    }
}
