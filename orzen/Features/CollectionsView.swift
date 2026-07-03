import SwiftUI

struct CollectionsView: View {
    // MARK: - Properties
    @ObservedObject private var collectionStore = CollectionStore.shared
    @ObservedObject private var episodeWatchStore = EpisodeWatchStore.shared
    var ownsNavigationStack = true
    private let contentHorizontalPadding: CGFloat = 16
    private let contentTopPadding: CGFloat = 8
    private let contentSpacing: CGFloat = 12
    
    // MARK: - Body
    var body: some View {
        if ownsNavigationStack {
            NavigationStack {
                content
            }
        } else {
            content
        }
    }

    private var content: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: contentSpacing) {
                Text("Collections")
                    .font(headerTitleFont)
                    .foregroundColor(.white)
                    .fontWeight(.bold)

                ScrollView {
                    LazyVGrid(
                        columns: OrzenLayout.posterGridColumns,
                        alignment: .leading,
                        spacing: OrzenLayout.current.gridVerticalSpacing
                    ) {
                        ForEach(collectionStore.collections) { collection in
                            NavigationLink {
                                CollectionDetailView(collection: collection)
                            } label: {
                                CollectionCard(collection: collection)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, contentHorizontalPadding)
            .padding(.top, contentTopPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        #if os(iOS)
        .toolbar(ownsNavigationStack ? .hidden : .visible, for: .navigationBar)
        .interactivePopGestureEnabled()
        #endif
    }

    private var headerTitleFont: Font {
        #if os(iOS)
        return .title2
        #else
        return .title
        #endif
    }
}

// MARK: - Collection Card View
struct CollectionCard: View {
    let collection: MediaCollection
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.1))

            Image(systemName: collection.systemImage)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(.white.opacity(0.38))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("\(collection.count)")
                .font(.caption.weight(.bold))
                .foregroundColor(.white.opacity(0.7))
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            LinearGradient(
                colors: [
                    Color.black.opacity(0),
                    Color.black.opacity(0.72)
                ],
                startPoint: .center,
                endPoint: .bottom
            )

            Text(collection.name)
                .font(collectionTitleFont)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .lineLimit(2)
                .shadow(radius: 4)
                .padding(collectionContentPadding)
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var collectionTitleFont: Font {
        #if os(iOS)
        return .subheadline
        #else
        return .headline
        #endif
    }

    private var collectionContentPadding: CGFloat {
        #if os(iOS)
        return 10
        #else
        return 12
        #endif
    }

    private var iconSize: CGFloat {
        #if os(iOS)
        return 32
        #else
        return 46
        #endif
    }
}

#Preview {
    CollectionsView()
} 
