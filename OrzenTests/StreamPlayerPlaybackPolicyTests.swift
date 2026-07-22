import XCTest
@testable import Orzen

final class StreamPlayerPlaybackPolicyTests: XCTestCase {
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
