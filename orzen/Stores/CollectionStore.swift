import Foundation

struct MediaCollection: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let systemImage: String
    let count: Int
}

struct LocalMediaCollections: Codable {
    var favoriteItems: [CatalogItem]
    var planToWatchItems: [CatalogItem]
    var watchedItems: [CatalogItem]
    var droppedItems: [CatalogItem]

    init(
        favoriteItems: [CatalogItem] = [],
        planToWatchItems: [CatalogItem] = [],
        watchedItems: [CatalogItem] = [],
        droppedItems: [CatalogItem] = []
    ) {
        self.favoriteItems = favoriteItems
        self.planToWatchItems = planToWatchItems
        self.watchedItems = watchedItems
        self.droppedItems = droppedItems
    }
}

@MainActor
final class CollectionStore: ObservableObject {
    static let shared = CollectionStore()

    static let favoritesID = "favorites"
    static let planToWatchID = "plan-to-watch"
    static let watchingID = "watching"
    static let watchedID = "watched"
    static let droppedID = "dropped"
    private static let storageKey = "OrzenCollectionsJSON"

    // These four arrays retain the original, remote-mode collections.
    @Published private(set) var favoriteItems: [CatalogItem] = []
    @Published private(set) var planToWatchItems: [CatalogItem] = []
    @Published private(set) var watchedItems: [CatalogItem] = []
    @Published private(set) var droppedItems: [CatalogItem] = []

    @Published private var localFavoriteItems: [CatalogItem] = []
    @Published private var localPlanToWatchItems: [CatalogItem] = []
    @Published private var localWatchedItems: [CatalogItem] = []
    @Published private var localDroppedItems: [CatalogItem] = []

    #if os(iOS)
    private var localCollectionSyncTask: Task<Void, Never>?
    #endif

    private init() {
        load()
    }

    var collections: [MediaCollection] {
        collections(for: .remote)
    }

    var localMediaCollections: LocalMediaCollections {
        LocalMediaCollections(
            favoriteItems: localFavoriteItems,
            planToWatchItems: localPlanToWatchItems,
            watchedItems: localWatchedItems,
            droppedItems: localDroppedItems
        )
    }

    func collections(for mediaKind: PlaybackMediaKind) -> [MediaCollection] {
        [
            MediaCollection(
                id: Self.favoritesID,
                name: "Favorites",
                systemImage: "heart.fill",
                count: favoriteItems(for: mediaKind).count
            ),
            MediaCollection(
                id: Self.planToWatchID,
                name: "Watchlist",
                systemImage: "clock.fill",
                count: planToWatchItems(for: mediaKind).count
            ),
            MediaCollection(
                id: Self.watchingID,
                name: "Watching",
                systemImage: "play.fill",
                count: PlaybackProgressStore.shared.watchingItems(for: mediaKind).count
            ),
            MediaCollection(
                id: Self.watchedID,
                name: "Watched",
                systemImage: "eye.fill",
                count: watchedItems(for: mediaKind).count
            ),
            MediaCollection(
                id: Self.droppedID,
                name: "Dropped",
                systemImage: "archivebox.fill",
                count: droppedItems(for: mediaKind).count
            )
        ]
    }

    func collection(id: MediaCollection.ID) -> MediaCollection? {
        collections.first { $0.id == id }
    }

    func items(
        in collectionID: MediaCollection.ID,
        mediaKind: PlaybackMediaKind = .remote
    ) -> [CatalogItem] {
        switch collectionID {
        case Self.favoritesID:
            return favoriteItems(for: mediaKind)
        case Self.planToWatchID:
            return planToWatchItems(for: mediaKind)
        case Self.watchingID:
            return PlaybackProgressStore.shared.watchingItems(for: mediaKind)
        case Self.watchedID:
            return watchedItems(for: mediaKind)
        case Self.droppedID:
            return droppedItems(for: mediaKind)
        default:
            return []
        }
    }

    func item(
        id itemID: CatalogItem.ID,
        in collectionID: MediaCollection.ID,
        mediaKind: PlaybackMediaKind = .remote
    ) -> CatalogItem? {
        items(in: collectionID, mediaKind: mediaKind).first { $0.id == itemID }
    }

    func favoriteItems(for mediaKind: PlaybackMediaKind) -> [CatalogItem] {
        mediaKind == .local ? localFavoriteItems : favoriteItems
    }

    func planToWatchItems(for mediaKind: PlaybackMediaKind) -> [CatalogItem] {
        mediaKind == .local ? localPlanToWatchItems : planToWatchItems
    }

    func watchedItems(for mediaKind: PlaybackMediaKind) -> [CatalogItem] {
        mediaKind == .local ? localWatchedItems : watchedItems
    }

    func droppedItems(for mediaKind: PlaybackMediaKind) -> [CatalogItem] {
        mediaKind == .local ? localDroppedItems : droppedItems
    }

    func isFavorite(_ item: CatalogItem, mediaKind: PlaybackMediaKind = .remote) -> Bool {
        favoriteItems(for: mediaKind).contains { $0.id == item.id }
    }

    func isInPlanToWatch(_ item: CatalogItem, mediaKind: PlaybackMediaKind = .remote) -> Bool {
        planToWatchItems(for: mediaKind).contains { $0.id == item.id }
    }

    func isWatched(_ item: CatalogItem, mediaKind: PlaybackMediaKind = .remote) -> Bool {
        watchedItems(for: mediaKind).contains { $0.id == item.id }
    }

    func isDropped(_ item: CatalogItem, mediaKind: PlaybackMediaKind = .remote) -> Bool {
        droppedItems(for: mediaKind).contains { $0.id == item.id }
    }

    func toggleFavorite(_ item: CatalogItem, mediaKind: PlaybackMediaKind = .remote) {
        if mediaKind == .local {
            toggle(item, in: &localFavoriteItems)
        } else {
            toggle(item, in: &favoriteItems)
        }
        save(syncLocalCollections: mediaKind == .local)
    }

    func togglePlanToWatch(_ item: CatalogItem, mediaKind: PlaybackMediaKind = .remote) {
        if mediaKind == .local {
            toggle(item, in: &localPlanToWatchItems)
            remove(item, from: &localWatchedItems)
            remove(item, from: &localDroppedItems)
        } else {
            toggle(item, in: &planToWatchItems)
            remove(item, from: &watchedItems)
            remove(item, from: &droppedItems)
        }
        save(syncLocalCollections: mediaKind == .local)
    }

    func toggleWatched(_ item: CatalogItem, mediaKind: PlaybackMediaKind = .remote) {
        let willMarkWatched = !isWatched(item, mediaKind: mediaKind)
        if mediaKind == .local {
            toggle(item, in: &localWatchedItems)
            remove(item, from: &localPlanToWatchItems)
            remove(item, from: &localDroppedItems)
        } else {
            toggle(item, in: &watchedItems)
            remove(item, from: &planToWatchItems)
            remove(item, from: &droppedItems)
        }
        if willMarkWatched {
            PlaybackProgressStore.shared.clearProgress(for: item, mediaKind: mediaKind)
        }
        save(syncLocalCollections: mediaKind == .local)
    }

    func setWatched(
        _ item: CatalogItem,
        isWatched: Bool,
        clearPlaybackProgress: Bool = true,
        mediaKind: PlaybackMediaKind = .remote
    ) {
        if mediaKind == .local {
            if isWatched {
                insert(item, in: &localWatchedItems)
                remove(item, from: &localPlanToWatchItems)
                remove(item, from: &localDroppedItems)
            } else {
                remove(item, from: &localWatchedItems)
            }
        } else if isWatched {
            insert(item, in: &watchedItems)
            remove(item, from: &planToWatchItems)
            remove(item, from: &droppedItems)
        } else {
            remove(item, from: &watchedItems)
        }

        if isWatched, clearPlaybackProgress {
            PlaybackProgressStore.shared.clearProgress(for: item, mediaKind: mediaKind)
        }

        save(syncLocalCollections: mediaKind == .local)
    }

    func toggleDropped(_ item: CatalogItem, mediaKind: PlaybackMediaKind = .remote) {
        let willDrop = !isDropped(item, mediaKind: mediaKind)
        if mediaKind == .local {
            toggle(item, in: &localDroppedItems)
            remove(item, from: &localPlanToWatchItems)
            remove(item, from: &localWatchedItems)
        } else {
            toggle(item, in: &droppedItems)
            remove(item, from: &planToWatchItems)
            remove(item, from: &watchedItems)
        }
        if willDrop {
            PlaybackProgressStore.shared.clearProgress(for: item, mediaKind: mediaKind)
        }
        save(syncLocalCollections: mediaKind == .local)
    }

    func setDropped(
        _ item: CatalogItem,
        isDropped: Bool,
        mediaKind: PlaybackMediaKind = .remote
    ) {
        if mediaKind == .local {
            if isDropped {
                insert(item, in: &localDroppedItems)
                remove(item, from: &localPlanToWatchItems)
                remove(item, from: &localWatchedItems)
            } else {
                remove(item, from: &localDroppedItems)
            }
        } else if isDropped {
            insert(item, in: &droppedItems)
            remove(item, from: &planToWatchItems)
            remove(item, from: &watchedItems)
        } else {
            remove(item, from: &droppedItems)
        }

        if isDropped {
            PlaybackProgressStore.shared.clearProgress(for: item, mediaKind: mediaKind)
        }

        save(syncLocalCollections: mediaKind == .local)
    }

    @discardableResult
    func mergeLocalCollections(_ incoming: LocalMediaCollections) -> LocalMediaCollections {
        localFavoriteItems = merge(localFavoriteItems, with: incoming.favoriteItems)
        localPlanToWatchItems = merge(localPlanToWatchItems, with: incoming.planToWatchItems)
        localWatchedItems = merge(localWatchedItems, with: incoming.watchedItems)
        localDroppedItems = merge(localDroppedItems, with: incoming.droppedItems)
        save()
        return localMediaCollections
    }

    #if os(iOS)
    func synchronizeLocalCollections() async {
        guard UserDefaults.standard.bool(forKey: LocalMediaModePreference.storageKey) else { return }
        let client = RemoteLocalMediaClient.shared
        guard client.isPaired else { return }

        do {
            let merged = try await client.syncLocalCollections(localMediaCollections)
            guard !Task.isCancelled else { return }
            _ = mergeLocalCollections(merged)
        } catch {
            // Local collections remain usable when the Mac is temporarily unreachable.
        }
    }

    func scheduleLocalCollectionSync() {
        localCollectionSyncTask?.cancel()
        localCollectionSyncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.synchronizeLocalCollections()
        }
    }
    #endif

    private func toggle(_ item: CatalogItem, in items: inout [CatalogItem]) {
        if let existingIndex = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: existingIndex)
        } else {
            items.insert(item, at: 0)
        }
    }

    private func insert(_ item: CatalogItem, in items: inout [CatalogItem]) {
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.insert(item, at: 0)
    }

    private func remove(_ item: CatalogItem, from items: inout [CatalogItem]) {
        items.removeAll { $0.id == item.id }
    }

    private func merge(_ existing: [CatalogItem], with incoming: [CatalogItem]) -> [CatalogItem] {
        var merged = existing
        var knownIDs = Set(existing.map(\.id))
        for item in incoming where knownIDs.insert(item.id).inserted {
            merged.append(item)
        }
        return merged
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }

        do {
            let storedCollections = try JSONDecoder().decode(StoredCollections.self, from: data)
            favoriteItems = storedCollections.favoriteItems
            planToWatchItems = storedCollections.planToWatchItems
            watchedItems = storedCollections.watchedItems
            droppedItems = storedCollections.droppedItems

            if let localCollections = storedCollections.localMediaCollections {
                localFavoriteItems = localCollections.favoriteItems
                localPlanToWatchItems = localCollections.planToWatchItems
                localWatchedItems = localCollections.watchedItems
                localDroppedItems = localCollections.droppedItems
            } else {
                // Older versions shared these lists with Local Media. Copy them so the
                // upgrade preserves what users saw in local mode while keeping remote lists intact.
                localFavoriteItems = favoriteItems
                localPlanToWatchItems = planToWatchItems
                localWatchedItems = watchedItems
                localDroppedItems = droppedItems
                save()
            }
        } catch {
            favoriteItems = []
            planToWatchItems = []
            watchedItems = []
            droppedItems = []
            localFavoriteItems = []
            localPlanToWatchItems = []
            localWatchedItems = []
            localDroppedItems = []
        }
    }

    private func save(syncLocalCollections: Bool = false) {
        let storedCollections = StoredCollections(
            favoriteItems: favoriteItems,
            planToWatchItems: planToWatchItems,
            watchedItems: watchedItems,
            droppedItems: droppedItems,
            localMediaCollections: localMediaCollections
        )
        guard let data = try? JSONEncoder().encode(storedCollections) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)

        #if os(iOS)
        if syncLocalCollections {
            scheduleLocalCollectionSync()
        }
        #endif
    }
}

private struct StoredCollections: Codable {
    let favoriteItems: [CatalogItem]
    let planToWatchItems: [CatalogItem]
    let watchedItems: [CatalogItem]
    let droppedItems: [CatalogItem]
    let localMediaCollections: LocalMediaCollections?

    init(
        favoriteItems: [CatalogItem] = [],
        planToWatchItems: [CatalogItem] = [],
        watchedItems: [CatalogItem] = [],
        droppedItems: [CatalogItem] = [],
        localMediaCollections: LocalMediaCollections? = nil
    ) {
        self.favoriteItems = favoriteItems
        self.planToWatchItems = planToWatchItems
        self.watchedItems = watchedItems
        self.droppedItems = droppedItems
        self.localMediaCollections = localMediaCollections
    }

    private enum CodingKeys: String, CodingKey {
        case favoriteItems
        case planToWatchItems
        case watchedItems
        case droppedItems
        case localMediaCollections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favoriteItems = try container.decodeIfPresent([CatalogItem].self, forKey: .favoriteItems) ?? []
        planToWatchItems = try container.decodeIfPresent([CatalogItem].self, forKey: .planToWatchItems) ?? []
        watchedItems = try container.decodeIfPresent([CatalogItem].self, forKey: .watchedItems) ?? []
        droppedItems = try container.decodeIfPresent([CatalogItem].self, forKey: .droppedItems) ?? []
        localMediaCollections = try container.decodeIfPresent(LocalMediaCollections.self, forKey: .localMediaCollections)
    }
}
