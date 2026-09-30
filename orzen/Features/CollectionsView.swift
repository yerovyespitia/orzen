import SwiftUI

struct CollectionsView: View {
    // MARK: - Properties
    @ObservedObject private var collectionStore = CollectionStore.shared
    @ObservedObject private var episodeWatchStore = EpisodeWatchStore.shared
    @ObservedObject private var playbackProgressStore = PlaybackProgressStore.shared
    @AppStorage(LocalMediaModePreference.storageKey) private var localMediaModeEnabled = false
    #if os(macOS)
    @ObservedObject private var downloadLibrary = LocalMediaLibraryStore.shared
    #else
    @State private var remoteDownloadVersions: [LocalMediaVersion] = []
    #endif
    var ownsNavigationStack = true
    var popToRootRequest = 0
    
    // MARK: - Body
    var body: some View {
        Group {
            if ownsNavigationStack {
                NavigationStack {
                    content
                        #if os(iOS)
                        .popNavigationToRoot(on: popToRootRequest)
                        #endif
                }
            } else {
                content
            }
        }
        #if os(iOS)
        .task(id: localMediaModeEnabled) {
            guard localMediaModeEnabled else {
                remoteDownloadVersions = []
                return
            }
            while !Task.isCancelled {
                remoteDownloadVersions = (try? await RemoteLocalMediaClient.shared.versions()) ?? []
                try? await Task.sleep(for: .seconds(3))
            }
        }
        #endif
    }

    private var screenContent: some View {
        OrzenScreen {
            #if os(macOS)
            OrzenScreenHeading(title: "Collections")
            #endif
        } content: {
            OrzenScreenScrollView(topPadding: collectionTopPadding) {
                collectionGrid
            }
            #if os(iOS)
            .scrollBounceBehavior(.always, axes: .vertical)
            #endif
        }
    }

    private var collectionTopPadding: CGFloat {
        #if os(iOS)
        OrzenScreenLayout.topPadding
        #else
        0
        #endif
    }

    private var content: some View {
        screenContent
        .navigationTitle("Collections")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        .interactivePopGestureEnabled()
        #endif
    }

    private var collectionGrid: some View {
        OrzenPosterGrid {
            ForEach(collectionStore.collections(for: playbackMediaKind)) { collection in
                NavigationLink {
                    CollectionDetailView(collection: collection)
                } label: {
                    CollectionCard(collection: collection)
                }
                .buttonStyle(PlainButtonStyle())
            }
            if localMediaModeEnabled {
                NavigationLink {
                    DownloadsView(ownsNavigationStack: false)
                } label: {
                    CollectionCard(collection: MediaCollection(
                        id: "downloads", name: "Downloads", systemImage: "arrow.down.to.line", count: downloadCount
                    ))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var playbackMediaKind: PlaybackMediaKind {
        localMediaModeEnabled ? .local : .remote
    }

    private var downloadCount: Int {
        #if os(macOS)
        let versions = downloadLibrary.versions
        #else
        let versions = remoteDownloadVersions
        #endif
        return Set(versions.map { "\($0.contentType.rawValue):\($0.catalogID)" }).count
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
