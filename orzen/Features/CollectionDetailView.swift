import SwiftUI

struct CollectionDetailView: View {
    // MARK: - Properties
    let collection: MediaCollection
    @ObservedObject private var collectionStore = CollectionStore.shared
    @ObservedObject private var episodeWatchStore = EpisodeWatchStore.shared
    @ObservedObject private var playbackProgressStore = PlaybackProgressStore.shared
    @AppStorage(LocalMediaModePreference.storageKey)
    private var localMediaModeEnabled = false
    @State private var selectedRoute: CollectionDetailRoute?
    // MARK: - Body
    var body: some View {
        OrzenCollectionScreen(title: currentCollection.name) {
            if items.isEmpty {
                DetailUnavailableView(
                    systemImage: currentCollection.systemImage,
                    title: "No items yet",
                    message: emptyMessage
                )
                .orzenScreenContentInset()
            } else {
                OrzenScreenScrollView {
                    OrzenPosterGrid {
                        ForEach(items) { item in
                            Button {
                                selectedRoute = .item(item.id)
                            } label: {
                                posterCard(for: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationDestination(item: $selectedRoute) { route in
            destination(for: route)
        }
    }

    private func posterCard(for item: CatalogItem) -> some View {
        CatalogPosterCard(
            item: item,
            showsDroppedContextAction: showsDroppedContextAction,
            onViewDetails: {
                selectedRoute = .item(item.id)
            }
        )
    }

    @ViewBuilder
    private func destination(for route: CollectionDetailRoute) -> some View {
        switch route {
        case let .item(itemID):
            if let item = collectionStore.item(
                id: itemID,
                in: collection.id,
                mediaKind: playbackMediaKind
            ) {
                InfoView(item: item)
            } else {
                DetailUnavailableView(
                    systemImage: "film",
                    title: "Title unavailable",
                    message: "This title is no longer in the collection."
                )
            }
        }
    }

    private var currentCollection: MediaCollection {
        collectionStore.collections(for: playbackMediaKind).first { $0.id == collection.id } ?? collection
    }

    private var items: [CatalogItem] {
        collectionStore.items(in: collection.id, mediaKind: playbackMediaKind)
    }

    private var playbackMediaKind: PlaybackMediaKind {
        localMediaModeEnabled ? .local : .remote
    }

    private var showsDroppedContextAction: Bool {
        collection.id == CollectionStore.watchingID
    }

    private var emptyMessage: String {
        if collection.id == CollectionStore.favoritesID {
            return "Favorite movies or series from their info screen."
        }

        if collection.id == CollectionStore.planToWatchID {
            return "Add movies or series from their info screen."
        }

        if collection.id == CollectionStore.watchedID {
            return "Mark movies or series as watched from their info screen."
        }

        if collection.id == CollectionStore.watchingID {
            return "Series with partially watched episodes appear here."
        }

        if collection.id == CollectionStore.droppedID {
            return "Mark movies or series as dropped from their info screen."
        }

        return "This collection does not have any saved titles."
    }
}

private enum CollectionDetailRoute: Hashable, Identifiable {
    case item(CatalogItem.ID)

    var id: String {
        switch self {
        case let .item(itemID):
            return itemID
        }
    }
}

#Preview {
    NavigationStack {
        CollectionDetailView(collection: MediaCollection(
            id: "favorites",
            name: "Favorites",
            systemImage: "heart.fill",
            count: 12,
        ))
    }
} 
