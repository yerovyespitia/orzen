import SwiftUI

struct CollectionDetailView: View {
    // MARK: - Properties
    let collection: MediaCollection
    var usesValueNavigation = false
    let onItemSelected: (CatalogItem) -> Void
    @ObservedObject private var collectionStore = CollectionStore.shared
    @ObservedObject private var episodeWatchStore = EpisodeWatchStore.shared
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
                                if usesValueNavigation {
                                    NavigationLink(value: CollectionRoute.item(item.id, collectionID: collection.id)) {
                                        posterCard(for: item)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Button {
                                        onItemSelected(item)
                                    } label: {
                                        posterCard(for: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, contentHorizontalPadding)
            .padding(.top, contentTopPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                onItemSelected(item)
            }
        )
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

#Preview {
    NavigationStack {
        CollectionDetailView(collection: MediaCollection(
            id: "favorites",
            name: "Favorites",
            systemImage: "heart.fill",
            count: 12,
        )) { _ in }
    }
} 
