import XCTest
@testable import Orzen

final class StreamSourceResolverTests: XCTestCase {
    func testMatchingSourcePrefersIdentifier() {
        let stored = TestFixtures.source(
            id: "stable",
            title: "Stored",
            url: URL(string: "https://example.com/old.m3u8")
        )
        let identifierMatch = TestFixtures.source(
            id: "stable",
            title: "Renamed",
            url: URL(string: "https://example.com/new.m3u8")
        )
        let urlMatch = TestFixtures.source(
            id: "other",
            title: "Stored",
            url: stored.playbackURL
        )

        XCTAssertEqual(
            StreamSourceResolver.matchingSource(for: stored, in: [urlMatch, identifierMatch]),
            identifierMatch
        )
    }

    func testMatchingSourceFallsBackToPlaybackURL() {
        let url = URL(string: "https://example.com/stable.m3u8")!
        let stored = TestFixtures.source(id: "old", title: "Old", url: url)
        let refreshed = TestFixtures.source(id: "new", title: "New", url: url)

        XCTAssertEqual(StreamSourceResolver.matchingSource(for: stored, in: [refreshed]), refreshed)
    }

    func testMatchingSourceFallsBackToTitle() {
        let stored = TestFixtures.source(id: "old", title: "Provider 1080p")
        let refreshed = TestFixtures.source(
            id: "new",
            title: "Provider 1080p",
            url: URL(string: "https://example.com/new.m3u8")
        )

        XCTAssertEqual(StreamSourceResolver.matchingSource(for: stored, in: [refreshed]), refreshed)
    }

    func testNoExactMatchUsesPlatformFallback() {
        let stored = TestFixtures.source(id: "stored", title: "Stored")
        let unsupported = TestFixtures.source(id: "mkv", title: "A MKV", url: URL(string: "https://example.com/a.mkv"))
        let supported = TestFixtures.source(id: "hls", title: "B HLS", url: URL(string: "https://example.com/b.m3u8"))

        #if os(iOS)
        XCTAssertEqual(StreamSourceResolver.matchingSource(for: stored, in: [unsupported, supported]), supported)
        #else
        XCTAssertEqual(StreamSourceResolver.matchingSource(for: stored, in: [unsupported, supported]), unsupported)
        #endif
    }
}
