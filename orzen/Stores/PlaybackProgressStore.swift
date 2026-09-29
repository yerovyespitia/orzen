import Foundation

enum PlaybackMediaKind: String, Codable, Sendable {
    case remote
    case local
}

struct PlaybackProgressEntry: Codable, Identifiable {
    let contentID: String
    let contentType: CinemetaType
    let item: CatalogItem
    let episode: CatalogEpisode?
    let source: StreamSource
    let sourceAddonID: LocalAddon.ID?
    let preferredSourceTitle: String?
    let title: String
    let subtitle: String
    var position: Double
    var duration: Double
    var trackSelections: PlaybackTrackSelections?
    var subtitleDelay: Double?
    var updatedAt: Date

    var id: String {
        Self.key(
            contentID: contentID,
            contentType: contentType,
            mediaKind: source.playbackMediaKind
        )
    }

    var progressFraction: Double {
        guard duration.isFinite, duration > 0, position.isFinite else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    var playbackRequest: StreamPlaybackRequest {
        let resolvedSource = source.resolvingAddonID(sourceAddonID)
        return StreamPlaybackRequest(
            source: resolvedSource,
            title: title,
            subtitle: subtitle,
            contentID: contentID,
            contentType: contentType,
            item: item,
            episode: episode,
            preferredSourceTitle: resolvedPreferredSourceTitle,
            initialTrackSelections: trackSelections,
            initialSubtitleDelay: subtitleDelay
        )
    }

    var resolvedPreferredSourceTitle: String {
        preferredSourceTitle ?? source.title
    }

    static func key(
        contentID: String,
        contentType: CinemetaType,
        mediaKind: PlaybackMediaKind = .remote
    ) -> String {
        "\(mediaKind.rawValue):\(contentType.rawValue):\(contentID)"
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

    private let userDefaults: UserDefaults

    private static let storageKey = "OrzenPlaybackProgressJSON"
    private static let localProgressTombstonesStorageKey = "OrzenLocalPlaybackProgressTombstonesJSON"
    private static let minimumResumePosition: Double = 1
    private static let seriesCompletionRemainingSeconds: Double = 180
    private static let movieCompletionRemainingSeconds: Double = 420

    private var localProgressTombstones: [String: Date] = [:]
    #if os(iOS)
    private var localMediaSyncTask: Task<Void, Never>?
    #endif

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        load()
    }

    var watchingItems: [CatalogItem] {
        watchingItems(for: .remote)
    }

    func watchingItems(for mediaKind: PlaybackMediaKind) -> [CatalogItem] {
        latestEntriesByItem(for: mediaKind).map(\.item)
    }

    func entry(
        for item: CatalogItem,
        mediaKind: PlaybackMediaKind = .remote
    ) -> PlaybackProgressEntry? {
        latestEntriesByItem(for: mediaKind).first { $0.item.id == item.id }
    }

    func entry(
        contentID: String,
        contentType: CinemetaType,
        mediaKind: PlaybackMediaKind = .remote
    ) -> PlaybackProgressEntry? {
        entries.first {
            $0.id == PlaybackProgressEntry.key(
                contentID: contentID,
                contentType: contentType,
                mediaKind: mediaKind
            )
        }
    }

    var localProgressSyncRecords: [LocalMediaProgressRecord] {
        let entryRecords = entries
            .filter { $0.source.playbackMediaKind == .local }
            .map(LocalMediaProgressRecord.init(entry:))
        let tombstoneRecords = localProgressTombstones.map { key, updatedAt in
            LocalMediaProgressRecord(deletedKey: key, updatedAt: updatedAt)
        }
        return (entryRecords + tombstoneRecords).sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.key < rhs.key
        }
    }

    @discardableResult
    func mergeLocalProgress(_ records: [LocalMediaProgressRecord]) -> [LocalMediaProgressRecord] {
        var mergedByKey = Dictionary(
            uniqueKeysWithValues: localProgressSyncRecords.map { ($0.key, $0) }
        )
        var didChange = false

        for record in records {
            guard isValidLocalProgressRecord(record) else { continue }
            guard shouldPrefer(record, over: mergedByKey[record.key]) else { continue }
            mergedByKey[record.key] = record
            didChange = true
        }

        if didChange {
            for record in mergedByKey.values {
                applyLocalProgressRecord(record)
            }
            save()
        }

        return localProgressSyncRecords
    }

    #if os(iOS)
    func synchronizeLocalProgress() async {
        let client = RemoteLocalMediaClient.shared
        guard client.isPaired else { return }

        do {
            let records = try await client.syncLocalProgress(localProgressSyncRecords)
            guard !Task.isCancelled else { return }
            _ = mergeLocalProgress(records)
        } catch {
            // Local playback remains available when the Mac is temporarily unreachable.
        }
    }

    func scheduleLocalProgressSync() {
        localMediaSyncTask?.cancel()
        localMediaSyncTask = Task { [weak self] in
            await self?.synchronizeLocalProgress()
        }
    }
    #endif

    func resumePosition(for request: StreamPlaybackRequest) -> Double? {
        guard let entry = entry(for: request),
              sourcesMatch(entry.source, request.source),
              entry.position >= Self.minimumResumePosition else {
            return nil
        }

        return entry.position
    }

    func trackSelections(for request: StreamPlaybackRequest) -> PlaybackTrackSelections? {
        guard let entry = entry(for: request),
              sourcesMatch(entry.source, request.source) else {
            return nil
        }

        return entry.trackSelections
    }

    func subtitleDelay(for request: StreamPlaybackRequest) -> Double {
        guard let entry = entry(for: request),
              sourcesMatch(entry.source, request.source) else {
            return 0
        }

        return entry.subtitleDelay ?? 0
    }

    func beginPlayback(for request: StreamPlaybackRequest) {
        if let entry = entry(for: request),
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
                sourceAddonID: source.addonID,
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
            clearProgress(for: request)
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
                sourceAddonID: request.source.addonID,
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
        let localKeys = entries
            .filter { $0.item.id == item.id && $0.source.playbackMediaKind == .local }
            .map(\.id)
        let deletionDate = Date()
        for key in localKeys {
            localProgressTombstones[key] = deletionDate
        }
        entries.removeAll { $0.item.id == item.id }
        save()
        #if os(iOS)
        if !localKeys.isEmpty {
            scheduleLocalProgressSync()
        }
        #endif
    }

    func clearProgress(contentID: String, contentType: CinemetaType) {
        clearProgress(contentID: contentID, contentType: contentType, mediaKind: .remote)
    }

    func clearProgress(
        contentID: String,
        contentType: CinemetaType,
        mediaKind: PlaybackMediaKind
    ) {
        let key = PlaybackProgressEntry.key(
            contentID: contentID,
            contentType: contentType,
            mediaKind: mediaKind
        )
        if mediaKind == .local {
            localProgressTombstones[key] = Date()
        }
        entries.removeAll { $0.id == key }
        save()
        #if os(iOS)
        if mediaKind == .local {
            scheduleLocalProgressSync()
        }
        #endif
    }

    func clearProgress(for request: StreamPlaybackRequest) {
        let key = PlaybackProgressEntry.key(
            contentID: request.contentID,
            contentType: request.contentType,
            mediaKind: request.source.playbackMediaKind
        )
        if request.source.playbackMediaKind == .local {
            localProgressTombstones[key] = Date()
        }
        entries.removeAll { $0.id == key }
        save()
        #if os(iOS)
        if request.source.playbackMediaKind == .local {
            scheduleLocalProgressSync()
        }
        #endif
    }

    func advanceWatchingProgressIfNeeded(
        afterMarkingWatched episode: CatalogEpisode,
        in item: CatalogItem,
        trackSelections: PlaybackTrackSelections? = nil,
        mediaKind: PlaybackMediaKind = .remote
    ) async {
        guard item.cinemetaType == .series,
              let currentEntry = entry(for: item, mediaKind: mediaKind),
              currentEntry.contentType == .series,
              currentEntry.episode?.id == episode.id else {
            return
        }

        clearProgress(contentID: episode.id, contentType: .series, mediaKind: mediaKind)

        guard mediaKind == .remote else { return }

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

    func progressFraction(
        for item: CatalogItem,
        mediaKind: PlaybackMediaKind = .remote
    ) -> Double {
        entry(for: item, mediaKind: mediaKind)?.progressFraction ?? 0
    }

    func watchingArtworkURL(
        for item: CatalogItem,
        mediaKind: PlaybackMediaKind = .remote
    ) -> URL? {
        guard let entry = entry(for: item, mediaKind: mediaKind) else {
            return item.backgroundURL ?? item.posterURL
        }

        switch entry.contentType {
        case .movie:
            return entry.item.backgroundURL ?? entry.item.posterURL
        case .series:
            return entry.episode?.thumbnailURL ?? entry.item.backgroundURL ?? entry.item.posterURL
        }
    }

    private func latestEntriesByItem(for mediaKind: PlaybackMediaKind) -> [PlaybackProgressEntry] {
        var seenItemIDs = Set<CatalogItem.ID>()

        return entries
            .filter { $0.source.playbackMediaKind == mediaKind }
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
        if entry.source.playbackMediaKind == .local {
            localProgressTombstones.removeValue(forKey: entry.id)
        }
        save()
    }

    private func isValidLocalProgressRecord(_ record: LocalMediaProgressRecord) -> Bool {
        guard record.key.hasPrefix("\(PlaybackMediaKind.local.rawValue):") else { return false }
        if let entry = record.entry {
            return entry.source.playbackMediaKind == .local && entry.id == record.key
        }
        return record.isDeleted
    }

    private func shouldPrefer(
        _ candidate: LocalMediaProgressRecord,
        over current: LocalMediaProgressRecord?
    ) -> Bool {
        guard let current else { return true }
        if candidate.updatedAt != current.updatedAt {
            return candidate.updatedAt > current.updatedAt
        }
        return candidate.isDeleted && !current.isDeleted
    }

    private func applyLocalProgressRecord(_ record: LocalMediaProgressRecord) {
        if record.isDeleted {
            entries.removeAll { $0.id == record.key }
            localProgressTombstones[record.key] = record.updatedAt
        } else if let entry = record.entry {
            entries.removeAll { $0.id == record.key }
            entries.insert(entry, at: 0)
            localProgressTombstones.removeValue(forKey: record.key)
        }
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
        entry(for: request)?.trackSelections
    }

    private func existingSubtitleDelay(for request: StreamPlaybackRequest) -> Double? {
        entry(for: request)?.subtitleDelay
    }

    private func entry(for request: StreamPlaybackRequest) -> PlaybackProgressEntry? {
        entry(
            contentID: request.contentID,
            contentType: request.contentType,
            mediaKind: request.source.playbackMediaKind
        )
    }

    private func load() {
        guard let data = userDefaults.data(forKey: Self.storageKey),
              let storedEntries = try? JSONDecoder().decode([PlaybackProgressEntry].self, from: data) else {
            loadLocalProgressTombstones()
            return
        }

        entries = storedEntries
        loadLocalProgressTombstones()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            userDefaults.set(data, forKey: Self.storageKey)
        }
        if let tombstoneData = try? JSONEncoder().encode(localProgressTombstones) {
            userDefaults.set(tombstoneData, forKey: Self.localProgressTombstonesStorageKey)
        }
    }

    private func loadLocalProgressTombstones() {
        guard let data = userDefaults.data(forKey: Self.localProgressTombstonesStorageKey),
              let tombstones = try? JSONDecoder().decode([String: Date].self, from: data) else {
            return
        }
        localProgressTombstones = tombstones
    }
}
