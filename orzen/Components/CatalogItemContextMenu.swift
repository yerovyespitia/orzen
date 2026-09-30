import SwiftUI

struct CatalogItemContextMenuModifier: ViewModifier {
    let item: CatalogItem
    let showsDroppedAction: Bool
    var onViewDetails: (() -> Void)?
    @AppStorage(LocalMediaModePreference.storageKey) private var localMediaModeEnabled = false
    @ObservedObject private var collectionStore = CollectionStore.shared
    @ObservedObject private var episodeWatchStore = EpisodeWatchStore.shared
    @State private var isConfirmingMarkAllWatched = false
    @State private var pendingWatchedEpisodes: [CatalogEpisode] = []

    private var collectionActions: CatalogItemCollectionActions {
        CatalogItemCollectionActions(item: item, mediaKind: playbackMediaKind)
    }

    private var playbackMediaKind: PlaybackMediaKind {
        localMediaModeEnabled ? .local : .remote
    }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if let onViewDetails {
                    Button(action: onViewDetails) {
                        Label("View Details", systemImage: "info.circle")
                    }
                }

                Button {
                    collectionStore.togglePlanToWatch(item, mediaKind: playbackMediaKind)
                } label: {
                    Label(listToggleTitle, systemImage: isAddedToList ? "checkmark" : "text.badge.plus")
                }

                Button {
                    collectionStore.toggleFavorite(item, mediaKind: playbackMediaKind)
                } label: {
                    Label(favoriteToggleTitle, systemImage: isFavorite ? "heart.fill" : "heart")
                }

                Button {
                    handleWatchedAction()
                } label: {
                    Label(watchedToggleTitle, systemImage: isWatched ? "eye.slash.fill" : "eye.fill")
                }

                if showsDroppedAction {
                    Button {
                        handleDroppedAction()
                    } label: {
                        Label(droppedToggleTitle, systemImage: isDropped ? "archivebox.fill" : "archivebox")
                    }
                }
            }
            .alert("Mark all episodes as watched?", isPresented: $isConfirmingMarkAllWatched) {
                Button("Cancel", role: .cancel) {
                    pendingWatchedEpisodes = []
                }
                Button("Mark All", action: markPendingSeriesWatched)
            } message: {
                Text("This series already has watched episodes. Marking all will mark every episode as watched.")
            }
    }

    private var listToggleTitle: String {
        collectionActions.listToggleTitle
    }

    private var favoriteToggleTitle: String {
        collectionActions.favoriteToggleTitle
    }

    private var watchedToggleTitle: String {
        collectionActions.watchedToggleTitle
    }

    private var droppedToggleTitle: String {
        collectionActions.droppedToggleTitle
    }

    private var isAddedToList: Bool {
        collectionActions.isAddedToList
    }

    private var isFavorite: Bool {
        collectionActions.isFavorite
    }

    private var isWatched: Bool {
        collectionActions.isWatched
    }

    private var isDropped: Bool {
        collectionActions.isDropped
    }

    private func handleWatchedAction() {
        guard item.cinemetaType == .series else {
            collectionStore.toggleWatched(item, mediaKind: playbackMediaKind)
            return
        }

        Task {
            let detail = await loadDetailForWatchedAction()
            applySeriesWatchedAction(episodes: detail.episodes)
        }
    }

    private func handleDroppedAction() {
        guard item.cinemetaType == .series, !isDropped else {
            collectionStore.toggleDropped(item, mediaKind: playbackMediaKind)
            return
        }

        Task {
            let detail = await loadDetailForWatchedAction()
            clearWatchedEpisodesBeforeDropping(episodes: detail.episodes)
        }
    }

    private func loadDetailForWatchedAction() async -> CatalogDetail {
        if let cachedDetail = await CinemetaClient.cachedDetail(for: item) {
            return cachedDetail
        }

        do {
            return try await CinemetaClient.fetchDetail(for: item)
        } catch {
            return .empty
        }
    }

    @MainActor
    private func applySeriesWatchedAction(episodes: [CatalogEpisode]) {
        let actions = CatalogItemCollectionActions(item: item, episodes: episodes, mediaKind: playbackMediaKind)
        if case let .confirmMarkAll(episodesToConfirm) = actions.applyWatchedAction() {
            pendingWatchedEpisodes = episodesToConfirm
            isConfirmingMarkAllWatched = true
        }
    }

    private func markPendingSeriesWatched() {
        markSeriesWatched(episodes: pendingWatchedEpisodes)
        pendingWatchedEpisodes = []
    }

    private func markSeriesWatched(episodes: [CatalogEpisode]) {
        CatalogItemCollectionActions(item: item, episodes: episodes, mediaKind: playbackMediaKind)
            .markSeriesWatched(episodes: episodes)
    }

    @MainActor
    private func clearWatchedEpisodesBeforeDropping(episodes: [CatalogEpisode]) {
        CatalogItemCollectionActions(item: item, episodes: episodes, mediaKind: playbackMediaKind)
            .applyDroppedAction()
    }
}

extension View {
    func catalogItemContextMenu(
        item: CatalogItem,
        showsDroppedAction: Bool = false,
        onViewDetails: (() -> Void)? = nil
    ) -> some View {
        modifier(CatalogItemContextMenuModifier(
            item: item,
            showsDroppedAction: showsDroppedAction,
            onViewDetails: onViewDetails
        ))
    }
}
