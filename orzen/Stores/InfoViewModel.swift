import Foundation

@MainActor
final class InfoViewModel: ObservableObject {
    let item: CatalogItem

    @Published var detail = CatalogDetail.empty
    @Published var isLoadingDetail = false
    @Published var hasLoadedDetail = false
    @Published var selectedSeason = 1
    @Published var detailErrorMessage: String?
    @Published var selectedEpisodeID: CatalogEpisode.ID?
    @Published var sources: [StreamSource] = []
    @Published var isLoadingSources = false
    @Published var hasLoadedSources = false
    @Published var sourceErrorMessage: String?
    @Published var selectedSourceAddonID: LocalAddon.ID?
    @Published private(set) var sourceAddons: [LocalAddon] = []
    @Published var pendingEpisodeScrollID: CatalogEpisode.ID?

    private let addonStore: LocalAddonStore
    private let playbackStore: StreamPlaybackStore
    private let episodeWatchStore: EpisodeWatchStore
    private let collectionStore: CollectionStore
    private var sourceRequestID: String?
    private var sourcesByAddonID: [LocalAddon.ID: [StreamSource]] = [:]
    private var hasAutoScrolledToWatchedEpisode = false

    init(item: CatalogItem) {
        self.item = item
        self.addonStore = .shared
        self.playbackStore = .shared
        self.episodeWatchStore = .shared
        self.collectionStore = .shared
    }

    var availableSeasons: [Int] {
        Set(detail.episodes.map { $0.season ?? 1 }).sorted()
    }

    var selectedSeasonEpisodes: [CatalogEpisode] {
        detail.episodes.filter { ($0.season ?? 1) == selectedSeason }
    }

    var selectedEpisode: CatalogEpisode? {
        guard let selectedEpisodeID else { return nil }
        return detail.episodes.first { $0.id == selectedEpisodeID }
    }

    var visibleSources: [StreamSource] { sources }

    func loadDetail() async {
        resetDetailState()

        guard item.cinemetaType != nil else {
            detail = .empty
            detailErrorMessage = nil
            hasLoadedDetail = true
            await loadMovieSourcesIfNeeded()
            return
        }

        if let cachedDetail = await CinemetaClient.cachedDetail(for: item) {
            setDetail(cachedDetail)
            detailErrorMessage = nil
            hasLoadedDetail = true
            await loadMovieSourcesIfNeeded()
            return
        }

        isLoadingDetail = true
        detailErrorMessage = nil

        do {
            setDetail(try await CinemetaClient.fetchDetail(for: item))
        } catch {
            detail = .empty
            detailErrorMessage = "Try again later or open another title."
        }

        hasLoadedDetail = true
        isLoadingDetail = false
        await loadMovieSourcesIfNeeded()
    }

    func syncSeriesCollectionState() {
        guard item.cinemetaType == .series else { return }

        if episodeWatchStore.hasWatchedEpisodes(for: item) {
            collectionStore.setDropped(item, isDropped: false)
        }

        collectionStore.setWatched(
            item,
            isWatched: episodeWatchStore.isSeriesFullyWatched(item, episodes: detail.episodes)
        )
    }

    func clearPendingEpisodeScroll() {
        pendingEpisodeScrollID = nil
    }

    func selectEpisode(_ episode: CatalogEpisode) {
        selectedEpisodeID = episode.id
        resetSourcesState()

        guard let type = item.cinemetaType else { return }

        Task {
            await loadSources(for: episode.id, type: type)
        }
    }

    func showEpisodes() {
        selectedEpisodeID = nil
        resetSourcesState()
    }

    func selectSourceAddon(_ addonID: LocalAddon.ID?) {
        guard addonID == nil || sourceAddons.contains(where: { $0.id == addonID }) else {
            return
        }
        guard selectedSourceAddonID != addonID else { return }

        selectedSourceAddonID = addonID
        sources = StreamSourceResolver.sortedSources(
            SourceAddonResultsPolicy.sources(
                for: addonID,
                addons: sourceAddons,
                sourcesByAddonID: sourcesByAddonID
            )
        )
    }

    func playSource(
        _ source: StreamSource,
        initialTrackSelections: PlaybackTrackSelections? = nil,
        attemptedSourceIDs: Set<StreamSource.ID> = []
    ) {
        guard let type = item.cinemetaType else { return }

        playbackStore.request = StreamPlaybackRequest(
            source: source,
            title: selectedEpisode?.playbackTitle ?? item.title,
            subtitle: item.title,
            contentID: selectedEpisode?.id ?? item.id,
            contentType: type,
            item: item,
            episode: selectedEpisode,
            initialTrackSelections: initialTrackSelections,
            attemptedSourceIDs: attemptedSourceIDs
        )
    }

    private func resetDetailState() {
        selectedSeason = 1
        pendingEpisodeScrollID = nil
        hasAutoScrolledToWatchedEpisode = false
        selectedEpisodeID = nil
        sources = []
        selectedSourceAddonID = nil
        sourceAddons = []
        sourcesByAddonID = [:]
        isLoadingSources = false
        hasLoadedSources = false
        sourceErrorMessage = nil
        sourceRequestID = nil
        hasLoadedDetail = false
    }

    private func resetSourcesState() {
        sources = []
        selectedSourceAddonID = nil
        sourceAddons = []
        sourcesByAddonID = [:]
        isLoadingSources = false
        hasLoadedSources = false
        sourceErrorMessage = nil
        sourceRequestID = nil
    }

    private func setDetail(_ loadedDetail: CatalogDetail) {
        detail = loadedDetail
        episodeWatchStore.registerSeries(item, episodes: loadedDetail.episodes)
        prepareInitialWatchedEpisodeScroll()
    }

    private func prepareInitialWatchedEpisodeScroll() {
        guard !hasAutoScrolledToWatchedEpisode,
              selectedEpisodeID == nil,
              !episodeWatchStore.isSeriesFullyWatched(item, episodes: detail.episodes),
              let episode = episodeWatchStore.lastWatchedEpisode(in: detail.episodes) else {
            return
        }

        selectedSeason = episode.season ?? 1
        pendingEpisodeScrollID = episode.id
        hasAutoScrolledToWatchedEpisode = true
    }

    private func loadMovieSourcesIfNeeded() async {
        guard item.cinemetaType == .movie else { return }
        await loadSources(for: item.id, type: .movie)
    }

    private func loadSources(
        for id: String,
        type: CinemetaType
    ) async {
        let requestID = UUID().uuidString
        sourceRequestID = requestID

        guard !addonStore.streamAddons.isEmpty else {
            guard sourceRequestID == requestID else { return }
            sources = []
            sourceErrorMessage = "Add a streaming addon from Addons to see available sources."
            hasLoadedSources = true
            isLoadingSources = false
            return
        }

        let compatibleAddons = addonStore.streamAddons.filter {
            $0.supports(resource: .stream, type: type, id: id)
        }

        guard !compatibleAddons.isEmpty else {
            guard sourceRequestID == requestID else { return }
            sources = []
            sourceErrorMessage = "No installed streaming addon supports this title."
            hasLoadedSources = true
            isLoadingSources = false
            return
        }

        isLoadingSources = true
        sourceErrorMessage = nil

        let loadedSourcesByAddonID = await StreamSourceResolver.fetchSourcesByAddon(
            from: compatibleAddons,
            type: type,
            id: id
        )

        guard sourceRequestID == requestID else { return }
        sourcesByAddonID = loadedSourcesByAddonID
        sourceAddons = SourceAddonResultsPolicy.availableAddons(
            from: compatibleAddons,
            sourcesByAddonID: loadedSourcesByAddonID
        )
        selectedSourceAddonID = nil
        sources = StreamSourceResolver.sortedSources(
            SourceAddonResultsPolicy.sources(
                for: nil,
                addons: sourceAddons,
                sourcesByAddonID: loadedSourcesByAddonID
            )
        )
        sourceErrorMessage = nil

        hasLoadedSources = true
        isLoadingSources = false
    }
}

enum SourceAddonResultsPolicy {
    static func availableAddons(
        from addons: [LocalAddon],
        sourcesByAddonID: [LocalAddon.ID: [StreamSource]]
    ) -> [LocalAddon] {
        addons.filter { !(sourcesByAddonID[$0.id] ?? []).isEmpty }
    }

    static func sources(
        for addonID: LocalAddon.ID?,
        addons: [LocalAddon],
        sourcesByAddonID: [LocalAddon.ID: [StreamSource]]
    ) -> [StreamSource] {
        if let addonID {
            return sourcesByAddonID[addonID] ?? []
        }

        return addons.flatMap { sourcesByAddonID[$0.id] ?? [] }
    }
}
