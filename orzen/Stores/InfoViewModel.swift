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
    @Published var selectedSourceFilter = SourceFilter.all
    @Published var pendingEpisodeScrollID: CatalogEpisode.ID?

    private let addonStore: LocalAddonStore
    private let playbackStore: StreamPlaybackStore
    private let episodeWatchStore: EpisodeWatchStore
    private let collectionStore: CollectionStore
    private var sourceRequestID: String?
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

    var hasSpanishSources: Bool {
        sources.contains { $0.sourceCategory == .spanish }
    }

    var visibleSources: [StreamSource] {
        switch selectedSourceFilter {
        case .all:
            return sources
        case .spanish:
            return sources.filter { $0.sourceCategory == .spanish }
        }
    }

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
        sourceRequestID = episode.id

        guard let type = item.cinemetaType else { return }

        Task {
            await loadSources(for: episode.id, type: type)
        }
    }

    func showEpisodes() {
        selectedEpisodeID = nil
        sources = []
        selectedSourceFilter = .all
        isLoadingSources = false
        hasLoadedSources = false
        sourceErrorMessage = nil
        sourceRequestID = nil
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
        selectedSourceFilter = .all
        hasLoadedSources = false
        sourceErrorMessage = nil
        sourceRequestID = nil
        hasLoadedDetail = false
    }

    private func resetSourcesState() {
        sources = []
        selectedSourceFilter = .all
        hasLoadedSources = false
        sourceErrorMessage = nil
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

    private func loadSources(for id: String, type: CinemetaType) async {
        sourceRequestID = id

        guard !addonStore.streamAddons.isEmpty else {
            guard sourceRequestID == id else { return }
            sources = []
            sourceErrorMessage = "Add Torrentio from Addons to see available sources."
            hasLoadedSources = true
            return
        }

        isLoadingSources = true
        sourceErrorMessage = nil

        let loadedSources = await StreamSourceResolver.fetchAllSources(
            from: addonStore.streamAddons,
            type: type,
            id: id
        )

        guard sourceRequestID == id else { return }
        sources = loadedSources
        if !hasSpanishSources {
            selectedSourceFilter = .all
        }
        if loadedSources.isEmpty {
            sourceErrorMessage = nil
        }

        hasLoadedSources = true
        isLoadingSources = false
    }
}
