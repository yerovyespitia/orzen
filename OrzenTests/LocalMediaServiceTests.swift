import XCTest
@testable import Orzen

@MainActor
final class LocalMediaServiceTests: XCTestCase {
    func testDownloadIndicatorRequiresCompletedVideo() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("video".utf8).write(to: root.appending(path: "movie.mp4"))
        let library = LocalMediaLibraryStore(root: root)
        let item = TestFixtures.item()
        var version = LocalMediaVersion(item: item, episode: nil, infoHash: "movie", torrentTitle: "Movie")
        version.videoRelativePath = "movie.mp4"

        for status in [LocalMediaVersion.Status.queued, .downloading, .paused, .failed] {
            version.status = status
            library.applySnapshot(.init(instanceID: UUID(), revision: 0, versions: [version]))
            XCTAssertFalse(library.hasDownload(for: item), "\(status) is not downloaded")
        }
        version.status = .completed
        library.applySnapshot(.init(instanceID: UUID(), revision: 0, versions: [version]))
        XCTAssertTrue(library.hasDownload(for: item))
        for path: String? in [nil, ""] {
            version.videoRelativePath = path
            library.applySnapshot(.init(instanceID: UUID(), revision: 0, versions: [version]))
            XCTAssertFalse(library.hasDownload(for: item))
        }
    }

    func testSeriesIndicatorTracksAnyCompletedEpisodeAndRemoval() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("video".utf8).write(to: root.appending(path: "episode.mp4"))
        let library = LocalMediaLibraryStore(root: root)
        let series = TestFixtures.item(type: .series)
        var completed = LocalMediaVersion(item: series,
            episode: TestFixtures.episode(id: "episode-1", number: 1), infoHash: "episode-1", torrentTitle: "S1E1")
        completed.status = .completed
        completed.videoRelativePath = "episode.mp4"
        let queued = LocalMediaVersion(item: series,
            episode: TestFixtures.episode(id: "episode-2", number: 2), infoHash: "episode-2", torrentTitle: "S1E2")
        library.applySnapshot(.init(instanceID: UUID(), revision: 0, versions: [completed, queued]))
        XCTAssertTrue(library.hasDownload(for: series))
        XCTAssertFalse(library.hasDownload(for: TestFixtures.item()))
        library.applySnapshot(.init(instanceID: UUID(), revision: 0, versions: [queued]))
        XCTAssertFalse(library.hasDownload(for: series))
        library.applySnapshot(.init(instanceID: UUID(), revision: 0, versions: [completed]))
        XCTAssertTrue(library.hasDownload(for: series))
        library.applySnapshot(.init(instanceID: UUID(), revision: 0, versions: []))
        XCTAssertFalse(library.hasDownload(for: series))
    }

    #if os(macOS)
    func testDownloadIndicatorRechecksRemovedFilesWithUnchangedSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appending(path: "movie.mp4")
        try Data("video".utf8).write(to: file)
        let library = LocalMediaLibraryStore(root: root)
        let item = TestFixtures.item()
        var version = LocalMediaVersion(item: item, episode: nil, infoHash: "movie", torrentTitle: "Movie")
        version.status = .completed
        version.videoRelativePath = "movie.mp4"
        let snapshot = LocalMediaLibrarySnapshot(instanceID: UUID(), revision: 0, versions: [version])
        library.applySnapshot(snapshot)
        XCTAssertTrue(library.hasDownload(for: item))
        try FileManager.default.removeItem(at: file)
        library.applySnapshot(snapshot)
        XCTAssertFalse(library.hasDownload(for: item))
    }
    #endif

    func testLocalCollectionsPersistWithoutChangingRemoteCollections() {
        let isolated = TestFixtures.isolatedDefaults()
        defer { isolated.defaults.removePersistentDomain(forName: isolated.suiteName) }
        let store = CollectionStore(userDefaults: isolated.defaults)
        let local = TestFixtures.item(id: "local")
        let remote = TestFixtures.item(id: "remote")
        store.toggleFavorite(local, mediaKind: .local)
        store.toggleFavorite(remote)
        let reloaded = CollectionStore(userDefaults: isolated.defaults)
        XCTAssertEqual(reloaded.favoriteItems(for: .local).map(\.id), [local.id])
        XCTAssertEqual(reloaded.favoriteItems(for: .remote).map(\.id), [remote.id])
    }

    func testLegacyLibraryVersionRoundTripsPathsAndDownloadState() throws {
        var version = LocalMediaVersion(item: TestFixtures.item(), episode: nil,
                                       infoHash: "ABC123", torrentTitle: "Movie 1080p")
        version.status = .paused
        version.magnetURI = "magnet:?xt=urn:btih:abc123"
        version.videoRelativePath = version.folderRelativePath + "/movie.mkv"
        let decoded = try JSONDecoder().decode(LocalMediaVersion.self, from: JSONEncoder().encode(version))
        XCTAssertEqual(decoded, version)
        XCTAssertEqual(decoded.infoHash, "abc123")
    }

    func testCollectionDeletionSurvivesStaleClientAndReload() {
        let isolated = TestFixtures.isolatedDefaults()
        defer { isolated.defaults.removePersistentDomain(forName: isolated.suiteName) }
        let store = CollectionStore(userDefaults: isolated.defaults)
        let item = TestFixtures.item()
        store.toggleFavorite(item, mediaKind: .local)
        let stale = store.localMediaCollections
        store.toggleFavorite(item, mediaKind: .local)
        _ = store.mergeLocalCollections(stale)
        XCTAssertFalse(store.isFavorite(item, mediaKind: .local))
        let reloaded = CollectionStore(userDefaults: isolated.defaults)
        _ = reloaded.mergeLocalCollections(LocalMediaCollections(favoriteItems: [item]))
        XCTAssertFalse(reloaded.isFavorite(item, mediaKind: .local))
        XCTAssertTrue(reloaded.localMediaCollections.records?.contains { $0.isDeleted } == true)
    }

    func testNewerCollectionChangeWinsOverOlderServerResponse() {
        let isolated = TestFixtures.isolatedDefaults()
        defer { isolated.defaults.removePersistentDomain(forName: isolated.suiteName) }
        let store = CollectionStore(userDefaults: isolated.defaults)
        let item = TestFixtures.item()
        store.toggleFavorite(item, mediaKind: .local)
        let future = LocalMediaCollectionRecord(collectionID: CollectionStore.favoritesID, item: item,
                                               updatedAt: Date(timeIntervalSinceNow: 60), isDeleted: true)
        _ = store.mergeLocalCollections(LocalMediaCollections(records: [future]))
        XCTAssertFalse(store.isFavorite(item, mediaKind: .local))
    }

    func testNewerCollectionMoveClearsStaleExclusiveMembership() {
        let isolated = TestFixtures.isolatedDefaults()
        defer { isolated.defaults.removePersistentDomain(forName: isolated.suiteName) }
        let store = CollectionStore(userDefaults: isolated.defaults)
        let item = TestFixtures.item()
        let before = Date()
        let records = [
            LocalMediaCollectionRecord(collectionID: CollectionStore.planToWatchID, item: item, updatedAt: before, isDeleted: false),
            LocalMediaCollectionRecord(collectionID: CollectionStore.watchedID, item: item, updatedAt: before.addingTimeInterval(10), isDeleted: false)
        ]
        _ = store.mergeLocalCollections(LocalMediaCollections(records: records))
        XCTAssertTrue(store.isWatched(item, mediaKind: .local))
        XCTAssertFalse(store.isInPlanToWatch(item, mediaKind: .local))
        _ = store.mergeLocalCollections(LocalMediaCollections(planToWatchItems: [item]))
        XCTAssertFalse(store.isInPlanToWatch(item, mediaKind: .local))
    }

    func testSnapshotRejectsOldResponseAndAcceptsServiceRestart() {
        var cursor = LocalMediaSnapshotCursor()
        let first = UUID()
        let restarted = UUID()
        XCTAssertTrue(cursor.accepts(.init(instanceID: first, revision: 5, versions: []), request: 2))
        XCTAssertFalse(cursor.accepts(.init(instanceID: first, revision: 4, versions: []), request: 3))
        XCTAssertTrue(cursor.accepts(.init(instanceID: restarted, revision: 0, versions: []), request: 4))
        XCTAssertFalse(cursor.accepts(.init(instanceID: first, revision: 10, versions: []), request: 3))
    }

    #if os(macOS)
    func testDesktopLibraryCannotWriteServerIndex() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LocalMediaLibraryStore(root: root)
        XCTAssertThrowsError(try library.reserveVersion(for: TestFixtures.item(), episode: nil,
                                                        infoHash: "abc", torrentTitle: "Movie"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "library.json").path))
    }

    func testServiceMigrationCopiesOnceWithoutWritingBackToApp() {
        let app = TestFixtures.isolatedDefaults()
        let service = TestFixtures.isolatedDefaults()
        defer {
            app.defaults.removePersistentDomain(forName: app.suiteName)
            service.defaults.removePersistentDomain(forName: service.suiteName)
        }
        app.defaults.set("original-token", forKey: "localMedia.accessToken")
        app.defaults.set(Data("progress".utf8), forKey: "OrzenPlaybackProgressJSON")
        LocalMediaServiceRuntime.prepareServiceDefaults(from: app.defaults, into: service.defaults)
        XCTAssertEqual(service.defaults.string(forKey: "localMedia.accessToken"), "original-token")
        XCTAssertEqual(service.defaults.data(forKey: "OrzenPlaybackProgressJSON"), Data("progress".utf8))
        service.defaults.set("service-token", forKey: "localMedia.accessToken")
        LocalMediaServiceRuntime.prepareServiceDefaults(from: app.defaults, into: service.defaults)
        XCTAssertEqual(service.defaults.string(forKey: "localMedia.accessToken"), "service-token")
        XCTAssertEqual(app.defaults.string(forKey: "localMedia.accessToken"), "original-token")
    }

    func testPairingCredentialsRemainStableAcrossLaunches() {
        let isolated = TestFixtures.isolatedDefaults()
        defer { isolated.defaults.removePersistentDomain(forName: isolated.suiteName) }
        isolated.defaults.set("123456", forKey: "localMedia.pairingCode")
        isolated.defaults.set("existing-token", forKey: "localMedia.accessToken")
        let first = LocalMediaServiceRuntime.credentials(defaults: isolated.defaults)
        let second = LocalMediaServiceRuntime.credentials(defaults: isolated.defaults)
        XCTAssertEqual(first.code, "123456")
        XCTAssertEqual(first.token, "existing-token")
        XCTAssertEqual(first.code, second.code)
        XCTAssertEqual(first.token, second.token)
    }
    #endif
}
