import XCTest
@testable import Orzen

@MainActor
final class PlaybackProgressStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: PlaybackProgressStore!

    override func setUp() async throws {
        let isolated = TestFixtures.isolatedDefaults()
        defaults = isolated.defaults
        suiteName = isolated.suiteName
        store = PlaybackProgressStore(userDefaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        suiteName = nil
    }

    func testCompletionThresholdsRemainDifferentForMoviesAndEpisodes() {
        XCTAssertFalse(store.isComplete(position: 1_000, duration: 1_421, contentType: .movie))
        XCTAssertTrue(store.isComplete(position: 1_001, duration: 1_421, contentType: .movie))
        XCTAssertFalse(store.isComplete(position: 1_000, duration: 1_181, contentType: .series))
        XCTAssertTrue(store.isComplete(position: 1_001, duration: 1_181, contentType: .series))
    }

    func testSavedProgressCanResumeWhenSourceIdentifierMatches() {
        let source = TestFixtures.source(id: "stable-id")
        let request = TestFixtures.request(source: source)

        store.saveProgress(for: request, position: 120, duration: 7_200)

        XCTAssertEqual(store.resumePosition(for: request), 120)
    }

    func testSavedProgressCanResumeWhenURLMatchesButIdentifierChanges() {
        let url = URL(string: "https://example.com/stable.m3u8")!
        let originalRequest = TestFixtures.request(source: TestFixtures.source(id: "old", url: url))
        let refreshedRequest = TestFixtures.request(source: TestFixtures.source(id: "new", url: url))

        store.saveProgress(for: originalRequest, position: 120, duration: 7_200)

        XCTAssertEqual(store.resumePosition(for: refreshedRequest), 120)
    }

    func testDifferentSourceDoesNotReuseResumeOrTrackState() {
        let original = TestFixtures.request(source: TestFixtures.source(id: "old"))
        let different = TestFixtures.request(
            source: TestFixtures.source(
                id: "new",
                url: URL(string: "https://other.example.com/video.m3u8")
            )
        )
        let selections = PlaybackTrackSelections(
            audio: PlaybackTrackChoice(id: "audio", title: "English", language: "en", isOff: false),
            subtitle: nil
        )

        store.saveProgress(
            for: original,
            position: 120,
            duration: 7_200,
            trackSelections: selections,
            subtitleDelay: 1.5
        )

        XCTAssertNil(store.resumePosition(for: different))
        XCTAssertNil(store.trackSelections(for: different))
        XCTAssertEqual(store.subtitleDelay(for: different), 0)
    }

    func testPositionBelowOneSecondIsNotResumableEvenWhenForced() {
        let request = TestFixtures.request()

        store.saveProgress(for: request, position: 0.5, duration: 7_200, force: true)

        XCTAssertNotNil(store.entry(contentID: request.contentID, contentType: .movie))
        XCTAssertNil(store.resumePosition(for: request))
    }

    func testTrackSelectionsAndSubtitleDelayArePersisted() {
        let request = TestFixtures.request()
        let selections = PlaybackTrackSelections(
            audio: PlaybackTrackChoice(id: "audio-en", title: "English", language: "en", isOff: false),
            subtitle: PlaybackTrackChoice(id: "sub-es", title: "Spanish", language: "es", isOff: false)
        )

        store.saveProgress(
            for: request,
            position: 120,
            duration: 7_200,
            trackSelections: selections,
            subtitleDelay: -0.75
        )

        XCTAssertEqual(store.trackSelections(for: request), selections)
        XCTAssertEqual(store.subtitleDelay(for: request), -0.75)

        let reloadedStore = PlaybackProgressStore(userDefaults: defaults)
        XCTAssertEqual(reloadedStore.trackSelections(for: request), selections)
        XCTAssertEqual(reloadedStore.subtitleDelay(for: request), -0.75)
    }

    func testPendingEpisodeProgressCarriesContinuationPreferences() {
        let item = TestFixtures.item(id: "series-1", type: .series)
        let episode = TestFixtures.episode(id: "series-1:1:2", number: 2)
        let source = TestFixtures.source(title: "Provider Branch")
        let selections = PlaybackTrackSelections(
            audio: PlaybackTrackChoice(id: "audio-en", title: "English", language: "en", isOff: false),
            subtitle: nil
        )

        store.savePendingProgress(
            for: item,
            episode: episode,
            source: source,
            preferredSourceTitle: "Original Branch",
            subtitle: item.title,
            trackSelections: selections,
            subtitleDelay: 0.4
        )

        let entry = store.entry(contentID: episode.id, contentType: .series)
        XCTAssertEqual(entry?.position, 0)
        XCTAssertEqual(entry?.duration, 0)
        XCTAssertEqual(entry?.episode?.id, episode.id)
        XCTAssertEqual(entry?.resolvedPreferredSourceTitle, "Original Branch")
        XCTAssertEqual(entry?.trackSelections, selections)
        XCTAssertEqual(entry?.subtitleDelay, 0.4)
    }

    func testCompletionClearsExistingProgress() {
        let request = TestFixtures.request()
        store.saveProgress(for: request, position: 120, duration: 7_200)
        XCTAssertNotNil(store.entry(contentID: request.contentID, contentType: .movie))

        store.saveProgress(for: request, position: 6_900, duration: 7_200)

        XCTAssertNil(store.entry(contentID: request.contentID, contentType: .movie))
    }

    func testInvalidProgressValuesAreIgnored() {
        let request = TestFixtures.request()

        store.saveProgress(for: request, position: .nan, duration: 7_200)
        store.saveProgress(for: request, position: -1, duration: 7_200)
        store.saveProgress(for: request, position: 10, duration: -.infinity)

        XCTAssertTrue(store.entries.isEmpty)
    }
}
