import SwiftUI

struct HomeView: View {
    var scrollToTopRequest = 0
    var popToRootRequest = 0

    @ObservedObject private var catalogStore = HomeCatalogStore.shared
    @ObservedObject private var playbackStore = StreamPlaybackStore.shared
    @ObservedObject private var progressStore = PlaybackProgressStore.shared
    @ObservedObject private var collectionStore = CollectionStore.shared
    @ObservedObject private var addonStore = LocalAddonStore.shared
    @ObservedObject private var bannerScrollStore = HomeBannerScrollStore.shared
    private let scrollTopID = "home-scroll-top"

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollViewReader { scrollProxy in
                    trackHomeScroll(
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                Color.clear
                                    .frame(height: 0)
                                    .id(scrollTopID)

                                FeaturedCarousel(items: catalogStore.featured)

                                if catalogStore.isLoading {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.white)
                                        .padding(.leading, OrzenLayout.current.contentLeadingInset)
                                        .padding(.bottom, 12)
                                }

                                if !progressStore.watchingItems.isEmpty {
                                    CatalogSectionView(
                                        title: "Watching",
                                        items: progressStore.watchingItems,
                                        cardStyle: .watching,
                                        showsDroppedContextAction: true,
                                        onItemSelected: playSavedProgress
                                    )
                                }

                                if !collectionStore.planToWatchItems.isEmpty {
                                    CatalogSectionView(
                                        title: "Watchlist",
                                        items: collectionStore.planToWatchItems
                                    )
                                }

                                ForEach(catalogStore.sections) { section in
                                    CatalogSectionView(
                                        title: section.title,
                                        items: section.items
                                    )
                                }
                            }
                            .frame(width: geometry.size.width, alignment: .leading)
                            .background(alignment: .top) {
                                VStack(spacing: 0) {
                                    Color.clear
                                        .frame(height: OrzenLayout.current.bannerHeight)

                                    Color.black
                                }
                            }
                        }
                        .ignoresSafeArea(.container, edges: .top)
                        .orzenTopScrollEdgeEffect()
                    )
                    .onChange(of: scrollToTopRequest) { _, _ in
                        scrollToTop(with: scrollProxy)
                    }
                }
            }
            .ignoresSafeArea(.container, edges: .top)
            #if os(iOS)
            .popNavigationToRoot(on: popToRootRequest)
            #endif
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .interactivePopGestureEnabled()
        #endif
        .task {
            catalogStore.loadIfNeeded()
        }
    }

    private func playSavedProgress(_ item: CatalogItem) {
        guard let entry = progressStore.entry(for: item) else { return }

        Task {
            playbackStore.request = await refreshedPlaybackRequest(for: entry)
        }
    }

    private func refreshedPlaybackRequest(for entry: PlaybackProgressEntry) async -> StreamPlaybackRequest {
        let storedRequest = entry.playbackRequest
        let matchingAddons = addonStore.streamAddons.filter {
            $0.name == entry.source.addonName && $0.sourceCategory == entry.source.sourceCategory
        }

        for addon in matchingAddons {
            let sources = await StreamSourceResolver.fetchAllSources(
                from: [addon],
                type: entry.contentType,
                id: entry.contentID
            )

            if let refreshedSource = StreamSourceResolver.matchingSource(for: entry.source, in: sources) {
                return StreamPlaybackRequest(
                    source: refreshedSource,
                    title: storedRequest.title,
                    subtitle: storedRequest.subtitle,
                    contentID: storedRequest.contentID,
                    contentType: storedRequest.contentType,
                    item: storedRequest.item,
                    episode: storedRequest.episode,
                    initialTrackSelections: storedRequest.initialTrackSelections
                )
            }
        }

        if entry.contentType == .series,
           let refreshedSource = await StreamSourceResolver.firstSource(
            from: addonStore.streamAddons,
            type: .series,
            id: entry.contentID
           ) {
            return StreamPlaybackRequest(
                source: refreshedSource,
                title: storedRequest.title,
                subtitle: storedRequest.subtitle,
                contentID: storedRequest.contentID,
                contentType: storedRequest.contentType,
                item: storedRequest.item,
                episode: storedRequest.episode,
                initialTrackSelections: storedRequest.initialTrackSelections
            )
        }

        return storedRequest
    }

    private func scrollToTop(with scrollProxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.18)) {
            scrollProxy.scrollTo(scrollTopID, anchor: .top)
        }
    }

    @ViewBuilder
    private func trackHomeScroll<Content: View>(_ content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 15.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, offset in
                bannerScrollStore.backgroundOffset = -offset
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
