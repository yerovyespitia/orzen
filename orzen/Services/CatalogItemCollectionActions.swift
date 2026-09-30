import Foundation

enum CatalogItemCollectionWatchedResult {
    case none
    case confirmMarkAll([CatalogEpisode])
}

@MainActor
struct CatalogItemCollectionActions {
    let item: CatalogItem
    let episodes: [CatalogEpisode]
    let mediaKind: PlaybackMediaKind

    private let collectionStore: CollectionStore
    private let episodeWatchStore: EpisodeWatchStore

    init(
        item: CatalogItem,
        episodes: [CatalogEpisode] = [],
        mediaKind: PlaybackMediaKind = .remote
    ) {
        self.item = item
        self.episodes = episodes
        self.mediaKind = mediaKind
        self.collectionStore = .shared
        self.episodeWatchStore = .shared
    }

    var listToggleTitle: String {
        isAddedToList ? "Remove from Watchlist" : "Add to Watchlist"
    }

    var favoriteToggleTitle: String {
        isFavorite ? "Remove from Favorites" : "Add to Favorites"
    }

    var watchedToggleTitle: String {
        if item.cinemetaType == .series {
            return isWatched ? "Remove watched episodes" : "Mark all episodes as watched"
        }

        return isWatched ? "Remove from Watched" : "Add to Watched"
    }

    var droppedToggleTitle: String {
        isDropped ? "Undrop" : "Drop"
    }

    var isAddedToList: Bool {
        collectionStore.isInPlanToWatch(item, mediaKind: mediaKind)
    }

    var isFavorite: Bool {
        collectionStore.isFavorite(item, mediaKind: mediaKind)
    }

    var isWatched: Bool {
        guard item.cinemetaType == .series, !episodes.isEmpty else {
            return collectionStore.isWatched(item, mediaKind: mediaKind)
        }

        return episodeWatchStore.isSeriesFullyWatched(item, episodes: episodes)
    }

    var isDropped: Bool {
        collectionStore.isDropped(item, mediaKind: mediaKind)
    }

    func togglePlanToWatch() {
        collectionStore.togglePlanToWatch(item, mediaKind: mediaKind)
    }

    func toggleFavorite() {
        collectionStore.toggleFavorite(item, mediaKind: mediaKind)
    }

    func applyWatchedAction() -> CatalogItemCollectionWatchedResult {
        guard item.cinemetaType == .series else {
            collectionStore.toggleWatched(item, mediaKind: mediaKind)
            return .none
        }

        guard !episodes.isEmpty else { return .none }

        if episodeWatchStore.isSeriesFullyWatched(item, episodes: episodes) {
            episodeWatchStore.clearWatched(item, episodes: episodes)
            collectionStore.setWatched(item, isWatched: false, mediaKind: mediaKind)
            return .none
        }

        if episodeWatchStore.hasWatchedEpisodes(for: item) {
            return .confirmMarkAll(episodes)
        }

        markSeriesWatched(episodes: episodes)
        return .none
    }

    func markSeriesWatched(episodes: [CatalogEpisode]) {
        episodeWatchStore.markAllWatched(item, episodes: episodes)
        collectionStore.setWatched(item, isWatched: true, mediaKind: mediaKind)
    }

    func applyDroppedAction() {
        guard item.cinemetaType == .series, !isDropped else {
            collectionStore.toggleDropped(item, mediaKind: mediaKind)
            return
        }

        if episodes.isEmpty {
            episodeWatchStore.clearWatched(item)
        } else {
            episodeWatchStore.clearWatched(item, episodes: episodes)
        }

        collectionStore.toggleDropped(item, mediaKind: mediaKind)
    }
}
