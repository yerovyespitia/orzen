import Foundation

@MainActor
final class EpisodeWatchStore: ObservableObject {
    static let shared = EpisodeWatchStore()

    @Published private(set) var watchedEpisodeIDs: Set<CatalogEpisode.ID> = []
    @Published private var seriesProgress: [CatalogItem.ID: WatchedSeriesProgress] = [:]

    private static let storageKey = "OrzenWatchedEpisodeIDs"
    private static let seriesStorageKey = "OrzenWatchedSeriesProgressJSON"

    private init() {
        load()
    }

    var inProgressSeries: [CatalogItem] {
        seriesProgress.values
            .filter { progress in
                !progress.watchedEpisodeIDs.isEmpty
                    && !progress.episodeIDs.isEmpty
                    && progress.watchedEpisodeIDs.count < progress.episodeIDs.count
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(\.item)
    }

    func watchingArtworkURL(for item: CatalogItem) -> URL? {
        switch item.cinemetaType {
        case .movie:
            return item.backgroundURL ?? item.posterURL
        case .series:
            return nextUnwatchedEpisode(for: item)?.thumbnailURL ?? item.backgroundURL ?? item.posterURL
        case .none:
            return item.backgroundURL ?? item.posterURL
        }
    }

    func isWatched(_ episode: CatalogEpisode) -> Bool {
        watchedEpisodeIDs.contains(episode.id)
    }

    func lastWatchedEpisode(in episodes: [CatalogEpisode]) -> CatalogEpisode? {
        episodes.last { watchedEpisodeIDs.contains($0.id) }
    }

    func nextUnwatchedEpisode(for item: CatalogItem) -> CatalogEpisode? {
        guard let progress = seriesProgress[item.id], !progress.episodes.isEmpty else {
            return nil
        }

        let watchedIDs = Set(progress.watchedEpisodeIDs)

        if let lastWatchedIndex = progress.episodes.lastIndex(where: { watchedIDs.contains($0.id) }) {
            let remainingEpisodes = progress.episodes.dropFirst(lastWatchedIndex + 1)
            if let nextEpisode = remainingEpisodes.first(where: { !watchedIDs.contains($0.id) }) {
                return nextEpisode
            }
        }

        return progress.episodes.first { !watchedIDs.contains($0.id) }
    }

    func nextEpisode(after episode: CatalogEpisode, in item: CatalogItem) -> CatalogEpisode? {
        guard let progress = seriesProgress[item.id],
              let currentIndex = progress.episodes.firstIndex(where: { $0.id == episode.id }) else {
            return nil
        }

        let nextIndex = progress.episodes.index(after: currentIndex)
        guard progress.episodes.indices.contains(nextIndex) else { return nil }
        return progress.episodes[nextIndex]
    }

    @discardableResult
    func toggleWatched(_ episode: CatalogEpisode) -> Bool {
        let wasWatched = watchedEpisodeIDs.contains(episode.id)
        toggleEpisodeID(episode.id)
        save()
        return !wasWatched
    }

    @discardableResult
    func toggleWatched(_ episode: CatalogEpisode, in item: CatalogItem, episodes: [CatalogEpisode]) -> Bool {
        let wasWatched = watchedEpisodeIDs.contains(episode.id)
        registerSeries(item, episodes: episodes)
        toggleEpisodeID(episode.id)
        updateSeries(itemID: item.id, episodeIDs: [episode.id])
        save()
        return !wasWatched
    }

    func markWatched(_ episode: CatalogEpisode, in item: CatalogItem) {
        watchedEpisodeIDs.insert(episode.id)

        guard var progress = seriesProgress[item.id] else {
            save()
            return
        }

        if !progress.watchedEpisodeIDs.contains(episode.id) {
            progress.watchedEpisodeIDs.append(episode.id)
        }
        progress.updatedAt = Date()
        seriesProgress[item.id] = progress
        save()
    }

    func markUnwatched(_ episode: CatalogEpisode, in item: CatalogItem) {
        watchedEpisodeIDs.remove(episode.id)

        guard var progress = seriesProgress[item.id] else {
            save()
            return
        }

        progress.watchedEpisodeIDs.removeAll { $0 == episode.id }
        progress.updatedAt = Date()
        seriesProgress[item.id] = progress
        save()
    }

    func registerSeries(_ item: CatalogItem, episodes: [CatalogEpisode]) {
        guard item.cinemetaType == .series, !episodes.isEmpty else { return }

        let episodeIDs = uniqueEpisodeIDs(from: episodes)
        let existingWatchedIDs = seriesProgress[item.id]?.watchedEpisodeIDs ?? []
        let watchedIDs = Set(existingWatchedIDs).union(watchedEpisodeIDs).intersection(episodeIDs)

        seriesProgress[item.id] = WatchedSeriesProgress(
            item: item,
            episodes: episodes,
            episodeIDs: episodeIDs,
            watchedEpisodeIDs: Array(watchedIDs),
            updatedAt: seriesProgress[item.id]?.updatedAt ?? Date()
        )
        save()
    }

    func hasWatchedEpisodes(for item: CatalogItem) -> Bool {
        guard let progress = seriesProgress[item.id] else { return false }
        return !progress.watchedEpisodeIDs.isEmpty
    }

    func isSeriesFullyWatched(_ item: CatalogItem, episodes: [CatalogEpisode]) -> Bool {
        let episodeIDs = seriesProgress[item.id]?.episodeIDs ?? uniqueEpisodeIDs(from: episodes)
        guard !episodeIDs.isEmpty else { return false }
        return episodeIDs.allSatisfy { watchedEpisodeIDs.contains($0) }
    }

    func isStoredSeriesFullyWatched(_ item: CatalogItem) -> Bool {
        guard let progress = seriesProgress[item.id],
              !progress.episodeIDs.isEmpty else {
            return false
        }

        return progress.episodeIDs.allSatisfy { watchedEpisodeIDs.contains($0) }
    }

    func markAllWatched(_ item: CatalogItem, episodes: [CatalogEpisode]) {
        registerSeries(item, episodes: episodes)
        let episodeIDs = uniqueEpisodeIDs(from: episodes)
        watchedEpisodeIDs.formUnion(episodeIDs)
        seriesProgress[item.id]?.watchedEpisodeIDs = episodeIDs
        seriesProgress[item.id]?.updatedAt = Date()
        save()
    }

    func clearWatched(_ item: CatalogItem, episodes: [CatalogEpisode]) {
        registerSeries(item, episodes: episodes)
        let episodeIDs = uniqueEpisodeIDs(from: episodes)
        watchedEpisodeIDs.subtract(episodeIDs)
        seriesProgress[item.id]?.watchedEpisodeIDs = []
        seriesProgress[item.id]?.updatedAt = Date()
        save()
    }

    func clearWatched(_ item: CatalogItem) {
        guard let progress = seriesProgress[item.id] else { return }
        watchedEpisodeIDs.subtract(progress.episodeIDs)
        seriesProgress[item.id]?.watchedEpisodeIDs = []
        seriesProgress[item.id]?.updatedAt = Date()
        save()
    }

    private func toggleEpisodeID(_ episodeID: CatalogEpisode.ID) {
        if watchedEpisodeIDs.contains(episodeID) {
            watchedEpisodeIDs.remove(episodeID)
        } else {
            watchedEpisodeIDs.insert(episodeID)
        }
    }

    private func updateSeries(itemID: CatalogItem.ID, episodeIDs: [CatalogEpisode.ID]) {
        guard var progress = seriesProgress[itemID] else { return }
        let watchedIDs = Set(progress.watchedEpisodeIDs)

        if episodeIDs.allSatisfy({ watchedIDs.contains($0) }) {
            progress.watchedEpisodeIDs.removeAll { episodeIDs.contains($0) }
        } else {
            progress.watchedEpisodeIDs = Array(watchedIDs.union(episodeIDs))
        }

        progress.updatedAt = Date()
        seriesProgress[itemID] = progress
    }

    private func uniqueEpisodeIDs(from episodes: [CatalogEpisode]) -> [CatalogEpisode.ID] {
        Array(Set(episodes.map(\.id))).sorted()
    }

    private func load() {
        let ids = UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? []
        watchedEpisodeIDs = Set(ids)

        guard let data = UserDefaults.standard.data(forKey: Self.seriesStorageKey),
              let progress = try? JSONDecoder().decode([WatchedSeriesProgress].self, from: data) else {
            return
        }

        seriesProgress = Dictionary(uniqueKeysWithValues: progress.map { ($0.item.id, $0) })
    }

    private func save() {
        let ids = watchedEpisodeIDs.sorted()
        UserDefaults.standard.set(ids, forKey: Self.storageKey)

        guard let data = try? JSONEncoder().encode(Array(seriesProgress.values)) else { return }
        UserDefaults.standard.set(data, forKey: Self.seriesStorageKey)
    }
}

private struct WatchedSeriesProgress: Codable {
    let item: CatalogItem
    let episodes: [CatalogEpisode]
    let episodeIDs: [CatalogEpisode.ID]
    var watchedEpisodeIDs: [CatalogEpisode.ID]
    var updatedAt: Date

    init(
        item: CatalogItem,
        episodes: [CatalogEpisode],
        episodeIDs: [CatalogEpisode.ID],
        watchedEpisodeIDs: [CatalogEpisode.ID],
        updatedAt: Date
    ) {
        self.item = item
        self.episodes = episodes
        self.episodeIDs = episodeIDs
        self.watchedEpisodeIDs = watchedEpisodeIDs
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        item = try container.decode(CatalogItem.self, forKey: .item)
        episodes = try container.decodeIfPresent([CatalogEpisode].self, forKey: .episodes) ?? []
        episodeIDs = try container.decode([CatalogEpisode.ID].self, forKey: .episodeIDs)
        watchedEpisodeIDs = try container.decode([CatalogEpisode.ID].self, forKey: .watchedEpisodeIDs)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
