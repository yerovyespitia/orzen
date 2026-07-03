import SwiftUI

struct CollectionDetailView: View {
    // MARK: - Properties
    let collection: MediaCollection
    @ObservedObject private var collectionStore = CollectionStore.shared
    @ObservedObject private var episodeWatchStore = EpisodeWatchStore.shared
    @State private var selectedRoute: CollectionDetailRoute?
    @Environment(\.dismiss) private var dismiss
    private let contentHorizontalPadding: CGFloat = 16
    private let contentTopPadding: CGFloat = 8
    private let contentSpacing: CGFloat = 12
    
    // MARK: - Body
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: contentSpacing) {
                // Header
                HStack {
                    Image(systemName: currentCollection.systemImage)
                        .font(.title2)
                        .foregroundColor(.gray)
                    
                    Text(currentCollection.name)
                        .font(headerTitleFont)
                        .foregroundColor(.white)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Text("\(currentCollection.count) items")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                // CatalogItem Grid
                if items.isEmpty {
                    DetailUnavailableView(
                        systemImage: currentCollection.systemImage,
                        title: "No items yet",
                        message: emptyMessage
                    )
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: OrzenLayout.posterGridColumns,
                            alignment: .leading,
                            spacing: OrzenLayout.current.gridVerticalSpacing
                        ) {
                            ForEach(items) { item in
                                NavigationLink {
                                    InfoView(item: item)
                                } label: {
                                    posterCard(for: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, contentHorizontalPadding)
            .padding(.top, contentTopPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationDestination(item: $selectedRoute) { route in
            destination(for: route)
        }
        .navigationTitle(currentCollection.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .interactivePopGestureEnabled()
        #endif
        .escapeKeyShortcut {
            dismiss()
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
            if let item = collectionStore.item(id: itemID, in: collection.id) {
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

    private var headerTitleFont: Font {
        #if os(iOS)
        return .title3
        #else
        return .title
        #endif
    }

    private var currentCollection: MediaCollection {
        collectionStore.collection(id: collection.id) ?? collection
    }

    private var items: [CatalogItem] {
        collectionStore.items(in: collection.id)
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
