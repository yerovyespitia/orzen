import Foundation

struct MediaCollection: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let systemImage: String
    let count: Int
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

    @Published private(set) var favoriteItems: [CatalogItem] = []
    @Published private(set) var planToWatchItems: [CatalogItem] = []
    @Published private(set) var watchedItems: [CatalogItem] = []
    @Published private(set) var droppedItems: [CatalogItem] = []

    private init() {
        load()
    }

    var collections: [MediaCollection] {
        collections(for: .remote)
    }

    func collections(for mediaKind: PlaybackMediaKind) -> [MediaCollection] {
        [
            MediaCollection(
                id: Self.favoritesID,
                name: "Favorites",
                systemImage: "heart.fill",
                count: favoriteItems.count
            ),
            MediaCollection(
                id: Self.planToWatchID,
                name: "Watchlist",
                systemImage: "clock.fill",
                count: planToWatchItems.count
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
                count: watchedItems.count
            ),
            MediaCollection(
                id: Self.droppedID,
                name: "Dropped",
                systemImage: "archivebox.fill",
                count: droppedItems.count
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
            return favoriteItems
        case Self.planToWatchID:
            return planToWatchItems
        case Self.watchingID:
            return PlaybackProgressStore.shared.watchingItems(for: mediaKind)
        case Self.watchedID:
            return watchedItems
        case Self.droppedID:
            return droppedItems
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

    func isFavorite(_ item: CatalogItem) -> Bool {
        favoriteItems.contains { $0.id == item.id }
    }

    func isInPlanToWatch(_ item: CatalogItem) -> Bool {
        planToWatchItems.contains { $0.id == item.id }
    }

    func isWatched(_ item: CatalogItem) -> Bool {
        watchedItems.contains { $0.id == item.id }
    }

    func isDropped(_ item: CatalogItem) -> Bool {
        droppedItems.contains { $0.id == item.id }
    }

    func toggleFavorite(_ item: CatalogItem) {
        toggle(item, in: &favoriteItems)
        save()
    }

    func togglePlanToWatch(_ item: CatalogItem) {
        toggle(item, in: &planToWatchItems)
        remove(item, from: &watchedItems)
        remove(item, from: &droppedItems)
        save()
    }

    func toggleWatched(_ item: CatalogItem) {
        let willMarkWatched = !isWatched(item)
        toggle(item, in: &watchedItems)
        remove(item, from: &planToWatchItems)
        remove(item, from: &droppedItems)
        if willMarkWatched {
            PlaybackProgressStore.shared.clearProgress(for: item)
        }
        save()
    }

    func setWatched(
        _ item: CatalogItem,
        isWatched: Bool,
        clearPlaybackProgress: Bool = true
    ) {
        if isWatched {
            insert(item, in: &watchedItems)
            remove(item, from: &planToWatchItems)
            remove(item, from: &droppedItems)
            if clearPlaybackProgress {
                PlaybackProgressStore.shared.clearProgress(for: item)
            }
        } else {
            remove(item, from: &watchedItems)
        }

        save()
    }

    func toggleDropped(_ item: CatalogItem) {
        let willDrop = !isDropped(item)
        toggle(item, in: &droppedItems)
        remove(item, from: &planToWatchItems)
        remove(item, from: &watchedItems)
        if willDrop {
            PlaybackProgressStore.shared.clearProgress(for: item)
        }
        save()
    }

    func setDropped(_ item: CatalogItem, isDropped: Bool) {
        if isDropped {
            insert(item, in: &droppedItems)
            remove(item, from: &planToWatchItems)
            remove(item, from: &watchedItems)
            PlaybackProgressStore.shared.clearProgress(for: item)
        } else {
            remove(item, from: &droppedItems)
        }

        save()
    }

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

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }

        do {
            let storedCollections = try JSONDecoder().decode(StoredCollections.self, from: data)
            favoriteItems = storedCollections.favoriteItems
            planToWatchItems = storedCollections.planToWatchItems
            watchedItems = storedCollections.watchedItems
            droppedItems = storedCollections.droppedItems
        } catch {
            favoriteItems = []
            planToWatchItems = []
            watchedItems = []
            droppedItems = []
        }
    }

    private func save() {
        let storedCollections = StoredCollections(
            favoriteItems: favoriteItems,
            planToWatchItems: planToWatchItems,
            watchedItems: watchedItems,
            droppedItems: droppedItems
        )
        guard let data = try? JSONEncoder().encode(storedCollections) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

private struct StoredCollections: Codable {
    let favoriteItems: [CatalogItem]
    let planToWatchItems: [CatalogItem]
    let watchedItems: [CatalogItem]
    let droppedItems: [CatalogItem]

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

    private enum CodingKeys: String, CodingKey {
        case favoriteItems
        case planToWatchItems
        case watchedItems
        case droppedItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favoriteItems = try container.decodeIfPresent([CatalogItem].self, forKey: .favoriteItems) ?? []
        planToWatchItems = try container.decodeIfPresent([CatalogItem].self, forKey: .planToWatchItems) ?? []
        watchedItems = try container.decodeIfPresent([CatalogItem].self, forKey: .watchedItems) ?? []
        droppedItems = try container.decodeIfPresent([CatalogItem].self, forKey: .droppedItems) ?? []
    }
}
