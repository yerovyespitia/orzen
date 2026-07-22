import XCTest
@testable import Orzen

@MainActor
final class EpisodeWatchStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: EpisodeWatchStore!
    private var item: CatalogItem!
    private var episodes: [CatalogEpisode]!

    override func setUp() async throws {
        let isolated = TestFixtures.isolatedDefaults()
        defaults = isolated.defaults
        suiteName = isolated.suiteName
        store = EpisodeWatchStore(userDefaults: defaults)
        item = TestFixtures.item(id: "series-1", type: .series)
        episodes = [
            TestFixtures.episode(id: "series-1:1:1", number: 1),
            TestFixtures.episode(id: "series-1:1:2", number: 2),
            TestFixtures.episode(id: "series-1:1:3", number: 3)
        ]
        store.registerSeries(item, episodes: episodes)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        item = nil
        episodes = nil
        defaults = nil
        suiteName = nil
    }

    func testNextEpisodeReturnsImmediateSequenceSuccessor() {
        XCTAssertEqual(store.nextEpisode(after: episodes[0], in: item)?.id, episodes[1].id)
        XCTAssertEqual(store.nextEpisode(after: episodes[1], in: item)?.id, episodes[2].id)
        XCTAssertNil(store.nextEpisode(after: episodes[2], in: item))
    }

    func testNextUnwatchedEpisodeStartsAtBeginning() {
        XCTAssertEqual(store.nextUnwatchedEpisode(for: item)?.id, episodes[0].id)
    }

    func testNextUnwatchedEpisodeContinuesAfterLastWatchedEpisode() {
        store.markWatched(episodes[0], in: item)
        XCTAssertEqual(store.nextUnwatchedEpisode(for: item)?.id, episodes[1].id)

        store.markWatched(episodes[1], in: item)
        XCTAssertEqual(store.nextUnwatchedEpisode(for: item)?.id, episodes[2].id)
    }

    func testFullyWatchedSeriesHasNoNextUnwatchedEpisode() {
        store.markAllWatched(item, episodes: episodes)

        XCTAssertTrue(store.isStoredSeriesFullyWatched(item))
        XCTAssertNil(store.nextUnwatchedEpisode(for: item))
    }

    func testMarkingEpisodeUnwatchedRestoresItToProgress() {
        store.markAllWatched(item, episodes: episodes)
        store.markUnwatched(episodes[1], in: item)

        XCTAssertFalse(store.isWatched(episodes[1]))
        XCTAssertFalse(store.isStoredSeriesFullyWatched(item))
    }

    func testMarkEpisodesBeforeWatchedHonorsSeasonAndEpisodeOrder() {
        let seasonTwoEpisode = TestFixtures.episode(id: "series-1:2:1", season: 2, number: 1)
        let allEpisodes = episodes + [seasonTwoEpisode]
        store.registerSeries(item, episodes: allEpisodes)

        store.markEpisodesBeforeWatched(seasonTwoEpisode, in: item, episodes: allEpisodes)

        XCTAssertTrue(episodes.allSatisfy(store.isWatched))
        XCTAssertFalse(store.isWatched(seasonTwoEpisode))
    }

    func testStateReloadsFromIsolatedDefaults() {
        store.markWatched(episodes[0], in: item)

        let reloadedStore = EpisodeWatchStore(userDefaults: defaults)

        XCTAssertTrue(reloadedStore.isWatched(episodes[0]))
        XCTAssertEqual(reloadedStore.nextUnwatchedEpisode(for: item)?.id, episodes[1].id)
    }
}
