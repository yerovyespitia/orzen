import Foundation

struct PlaybackProgressEntry: Codable, Identifiable {
    let contentID: String
    let contentType: CinemetaType
    let item: CatalogItem
    let episode: CatalogEpisode?
    let source: StreamSource
    let preferredSourceTitle: String?
    let title: String
    let subtitle: String
    var position: Double
    var duration: Double
    var trackSelections: PlaybackTrackSelections?
    var subtitleDelay: Double?
    var updatedAt: Date

    var id: String {
        Self.key(contentID: contentID, contentType: contentType)
    }

    var progressFraction: Double {
        guard duration.isFinite, duration > 0, position.isFinite else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    var playbackRequest: StreamPlaybackRequest {
        StreamPlaybackRequest(
            source: source,
            title: title,
            subtitle: subtitle,
            contentID: contentID,
            contentType: contentType,
            item: item,
            episode: episode,
            preferredSourceTitle: resolvedPreferredSourceTitle,
            initialTrackSelections: trackSelections
        )
    }

    var resolvedPreferredSourceTitle: String {
        preferredSourceTitle ?? source.title
    }

    static func key(contentID: String, contentType: CinemetaType) -> String {
        "\(contentType.rawValue):\(contentID)"
    }
}

struct PlaybackTrackSelections: Codable, Equatable, Sendable {
    var audio: PlaybackTrackChoice?
    var subtitle: PlaybackTrackChoice?
}

struct PlaybackTrackChoice: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let language: String?
    let isOff: Bool
}

@MainActor
final class PlaybackProgressStore: ObservableObject {
    static let shared = PlaybackProgressStore()

    @Published private(set) var entries: [PlaybackProgressEntry] = []

    private static let storageKey = "OrzenPlaybackProgressJSON"
    private static let minimumResumePosition: Double = 1
    private static let seriesCompletionRemainingSeconds: Double = 180
    private static let movieCompletionRemainingSeconds: Double = 420

    private init() {
        load()
    }

    var watchingItems: [CatalogItem] {
        latestEntriesByItem.map(\.item)
    }

    func entry(for item: CatalogItem) -> PlaybackProgressEntry? {
        latestEntriesByItem.first { $0.item.id == item.id }
    }

    func entry(contentID: String, contentType: CinemetaType) -> PlaybackProgressEntry? {
        entries.first { $0.id == PlaybackProgressEntry.key(contentID: contentID, contentType: contentType) }
    }

    func resumePosition(for request: StreamPlaybackRequest) -> Double? {
        guard let entry = entry(contentID: request.contentID, contentType: request.contentType),
              sourcesMatch(entry.source, request.source),
              entry.position >= Self.minimumResumePosition else {
            return nil
        }

        return entry.position
    }

    func trackSelections(for request: StreamPlaybackRequest) -> PlaybackTrackSelections? {
        guard let entry = entry(contentID: request.contentID, contentType: request.contentType),
              sourcesMatch(entry.source, request.source) else {
            return nil
        }

        return entry.trackSelections
    }

    func subtitleDelay(for request: StreamPlaybackRequest) -> Double {
        guard let entry = entry(contentID: request.contentID, contentType: request.contentType),
              sourcesMatch(entry.source, request.source) else {
            return 0
        }

        return entry.subtitleDelay ?? 0
    }

    func beginPlayback(for request: StreamPlaybackRequest) {
        if let entry = entry(contentID: request.contentID, contentType: request.contentType),
           sourcesMatch(entry.source, request.source) {
            saveProgress(
                for: request,
                position: entry.position,
                duration: entry.duration,
                trackSelections: entry.trackSelections,
                subtitleDelay: entry.subtitleDelay,
                force: true
            )
            return
        }
    }

    func savePendingProgress(
        for item: CatalogItem,
        episode: CatalogEpisode,
        source: StreamSource,
        preferredSourceTitle: String? = nil,
        subtitle: String,
        trackSelections: PlaybackTrackSelections? = nil,
        subtitleDelay: Double? = nil
    ) {
        saveEntry(
            PlaybackProgressEntry(
                contentID: episode.id,
                contentType: .series,
                item: item,
                episode: episode,
                source: source,
                preferredSourceTitle: preferredSourceTitle ?? source.title,
                title: episode.playbackTitle,
                subtitle: subtitle,
                position: 0,
                duration: 0,
                trackSelections: trackSelections,
                subtitleDelay: subtitleDelay,
                updatedAt: Date()
            )
        )
    }

    func saveProgress(
        for request: StreamPlaybackRequest,
        position: Double,
        duration: Double,
        trackSelections: PlaybackTrackSelections? = nil,
        subtitleDelay: Double? = nil,
        force: Bool = false
    ) {
        guard let item = request.item,
              position.isFinite,
              duration.isFinite,
              position >= 0,
              duration >= 0 else {
            return
        }

        if shouldClearProgress(position: position, duration: duration, contentType: request.contentType) {
            clearProgress(contentID: request.contentID, contentType: request.contentType)
            return
        }

        guard force || position >= Self.minimumResumePosition else { return }

        if request.contentType == .series,
           position >= Self.minimumResumePosition,
           let episode = request.episode,
           EpisodeWatchStore.shared.isWatched(episode) {
            EpisodeWatchStore.shared.markUnwatched(episode, in: item)
            CollectionStore.shared.setWatched(item, isWatched: false)
        }

        saveEntry(
            PlaybackProgressEntry(
                contentID: request.contentID,
                contentType: request.contentType,
                item: item,
                episode: request.episode,
                source: request.source,
                preferredSourceTitle: request.preferredSourceTitle,
                title: request.title,
                subtitle: request.subtitle,
                position: position,
                duration: duration,
                trackSelections: trackSelections ?? existingTrackSelections(for: request),
                subtitleDelay: subtitleDelay ?? existingSubtitleDelay(for: request),
                updatedAt: Date()
            )
        )
    }

    func isComplete(position: Double, duration: Double, contentType: CinemetaType) -> Bool {
        guard position.isFinite, duration.isFinite else { return false }
        return shouldClearProgress(position: position, duration: duration, contentType: contentType)
    }

    func clearProgress(for item: CatalogItem) {
        entries.removeAll { $0.item.id == item.id }
        save()
    }

    func clearProgress(contentID: String, contentType: CinemetaType) {
        entries.removeAll { $0.id == PlaybackProgressEntry.key(contentID: contentID, contentType: contentType) }
        save()
    }

    func clearProgress(for request: StreamPlaybackRequest) {
        entries.removeAll { entry in
            entry.id == PlaybackProgressEntry.key(contentID: request.contentID, contentType: request.contentType)
                && sourcesMatch(entry.source, request.source)
        }
        save()
    }

    func advanceWatchingProgressIfNeeded(
        afterMarkingWatched episode: CatalogEpisode,
        in item: CatalogItem,
        trackSelections: PlaybackTrackSelections? = nil
    ) async {
        guard item.cinemetaType == .series,
              let currentEntry = entry(for: item),
              currentEntry.contentType == .series,
              currentEntry.episode?.id == episode.id else {
            return
        }

        clearProgress(contentID: episode.id, contentType: .series)

        guard let nextEpisode = EpisodeWatchStore.shared.nextUnwatchedEpisode(for: item),
              !EpisodeWatchStore.shared.isStoredSeriesFullyWatched(item) else {
            return
        }

        let pendingTrackSelections = trackSelections ?? currentEntry.trackSelections
        let pendingSubtitleDelay = currentEntry.subtitleDelay
        savePendingProgress(
            for: item,
            episode: nextEpisode,
            source: currentEntry.source,
            preferredSourceTitle: currentEntry.resolvedPreferredSourceTitle,
            subtitle: item.title,
            trackSelections: pendingTrackSelections,
            subtitleDelay: pendingSubtitleDelay
        )

        guard let refreshedSource = await StreamSourceResolver.continuingSource(
            after: currentEntry.source,
            preferredTitle: currentEntry.resolvedPreferredSourceTitle,
            from: LocalAddonStore.shared.streamAddons,
            type: .series,
            id: nextEpisode.id
        ) else {
            return
        }

        savePendingProgress(
            for: item,
            episode: nextEpisode,
            source: refreshedSource,
            preferredSourceTitle: currentEntry.resolvedPreferredSourceTitle,
            subtitle: item.title,
            trackSelections: pendingTrackSelections,
            subtitleDelay: pendingSubtitleDelay
        )
    }

    func progressFraction(for item: CatalogItem) -> Double {
        entry(for: item)?.progressFraction ?? 0
    }

    func watchingArtworkURL(for item: CatalogItem) -> URL? {
        guard let entry = entry(for: item) else {
            return item.backgroundURL ?? item.posterURL
        }

        switch entry.contentType {
        case .movie:
            return entry.item.backgroundURL ?? entry.item.posterURL
        case .series:
            return entry.episode?.thumbnailURL ?? entry.item.backgroundURL ?? entry.item.posterURL
        }
    }

    private var latestEntriesByItem: [PlaybackProgressEntry] {
        var seenItemIDs = Set<CatalogItem.ID>()

        return entries
            .sorted { $0.updatedAt > $1.updatedAt }
            .filter { entry in
                guard !seenItemIDs.contains(entry.item.id) else { return false }
                seenItemIDs.insert(entry.item.id)
                return true
            }
    }

    private func saveEntry(_ entry: PlaybackProgressEntry) {
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        save()
    }

    private func sourcesMatch(_ lhs: StreamSource, _ rhs: StreamSource) -> Bool {
        lhs.id == rhs.id || lhs.playbackURL == rhs.playbackURL
    }

    private func shouldClearProgress(position: Double, duration: Double, contentType: CinemetaType) -> Bool {
        guard duration > 0 else { return false }

        let remainingSeconds = max(duration - position, 0)
        switch contentType {
        case .movie:
            return remainingSeconds <= Self.movieCompletionRemainingSeconds
        case .series:
            return remainingSeconds <= Self.seriesCompletionRemainingSeconds
        }
    }

    private func existingTrackSelections(for request: StreamPlaybackRequest) -> PlaybackTrackSelections? {
        entry(contentID: request.contentID, contentType: request.contentType)?.trackSelections
    }

    private func existingSubtitleDelay(for request: StreamPlaybackRequest) -> Double? {
        entry(contentID: request.contentID, contentType: request.contentType)?.subtitleDelay
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let storedEntries = try? JSONDecoder().decode([PlaybackProgressEntry].self, from: data) else {
            return
        }

        entries = storedEntries
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
