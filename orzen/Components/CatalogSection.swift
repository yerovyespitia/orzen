import SwiftUI

struct CatalogSectionView: View {
    enum CardStyle {
        case poster
        case watching
    }

    let title: String
    let items: [CatalogItem]
    var cardStyle: CardStyle = .poster
    var showsDroppedContextAction = false
    var onItemSelected: ((CatalogItem) -> Void)?
    @State private var detailItemFromContextMenu: CatalogItem?
    @State private var isShowingContextMenuDetail = false

    private var metrics: OrzenLayout.Metrics {
        OrzenLayout.current
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline).bold()
                .foregroundColor(.white)
                .padding(.leading, metrics.contentLeadingInset)
                .padding(.trailing, metrics.contentTrailingInset)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { item in
                        if let onItemSelected {
                            Button {
                                onItemSelected(item)
                            } label: {
                                card(for: item)
                            }
                            .buttonStyle(.plain)
                            .frame(width: cardWidth, height: cardHeight)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1 : 0.82)
                                    .scaleEffect(phase.isIdentity ? 1 : 0.98)
                            }
                        } else {
                            NavigationLink(destination: InfoView(item: item)) {
                                card(for: item)
                            }
                            .buttonStyle(.plain)
                            .frame(width: cardWidth, height: cardHeight)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1 : 0.82)
                                    .scaleEffect(phase.isIdentity ? 1 : 0.98)
                            }
                        }
                    }
                }
                .padding(.leading, metrics.contentLeadingInset)
                .padding(.trailing, metrics.contentTrailingInset)
                .padding(.vertical, 2)
            }
        }
        .padding(.bottom, 22)
        .navigationDestination(isPresented: $isShowingContextMenuDetail) {
            if let detailItemFromContextMenu {
                InfoView(item: detailItemFromContextMenu)
            }
        }
    }

    @ViewBuilder
    private func card(for item: CatalogItem) -> some View {
        switch cardStyle {
        case .poster:
            SeriesCard(
                item: item,
                showsDroppedContextAction: showsDroppedContextAction,
                onViewDetails: {
                    showContextMenuDetail(for: item)
                }
            )
        case .watching:
            WatchingCard(
                item: item,
                showsDroppedContextAction: showsDroppedContextAction,
                onViewDetails: {
                    showContextMenuDetail(for: item)
                }
            )
        }
    }

    private func showContextMenuDetail(for item: CatalogItem) {
        detailItemFromContextMenu = item
        isShowingContextMenuDetail = true
    }

    private var cardWidth: CGFloat {
        switch cardStyle {
        case .poster:
            metrics.posterWidth
        case .watching:
            metrics.watchingWidth
        }
    }

    private var cardHeight: CGFloat {
        switch cardStyle {
        case .poster:
            metrics.posterHeight
        case .watching:
            metrics.watchingHeight
        }
    }
}

private struct WatchingCard: View {
    let item: CatalogItem
    var showsDroppedContextAction = false
    var onViewDetails: (() -> Void)?

    @ObservedObject private var progressStore = PlaybackProgressStore.shared
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork

            LinearGradient(
                colors: [
                    Color.black.opacity(0),
                    Color.black.opacity(0.72)
                ],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .shadow(radius: 4)

                if let watchingEpisodeLabel {
                    Text(watchingEpisodeLabel)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.78))
                        .lineLimit(1)
                }

                progressBar
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(isHovered ? 0.2 : 0.08), lineWidth: 1)
        }
        .scaleEffect(isHovered ? 1.015 : 1)
        .animation(.easeInOut(duration: 0.16), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .catalogItemContextMenu(
            item: item,
            showsDroppedAction: showsDroppedContextAction,
            onViewDetails: onViewDetails
        )
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkURL = progressStore.watchingArtworkURL(for: item), artworkURL != item.backgroundURL {
            CachedRemoteImage(url: artworkURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: { _ in
                bannerArtwork
            }
        } else {
            bannerArtwork
        }
    }

    @ViewBuilder
    private var bannerArtwork: some View {
        if let bannerURL = item.backgroundURL {
            CachedRemoteImage(url: bannerURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: { _ in
                OrzenArtworkPlaceholder(style: .backdrop)
            }
        } else {
            OrzenArtworkPlaceholder(style: .backdrop)
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.22))

                Capsule()
                    .fill(Color.white.opacity(0.96))
                    .frame(width: max(0, proxy.size.width * progressFraction))
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
    }

    private var progressFraction: Double {
        progressStore.progressFraction(for: item)
    }

    private var watchingEpisodeLabel: String? {
        guard item.cinemetaType == .series,
              let episode = progressStore.entry(for: item)?.episode else {
            return nil
        }

        return episode.metadata.first
    }
}

#Preview {
    CatalogSectionView(
        title: "Last Watched",
        items: lastWatched
    )
} 
