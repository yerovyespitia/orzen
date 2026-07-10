//
//  Sidebar.swift
//  Orzen
//
//  Created by Yerovy Espitia on 11/05/25.
//

import SwiftUI

enum OrzenLayout {
    static let sidebarDefaultWidth: CGFloat = 230
    static let contentLeadingInset: CGFloat = 24
    static let contentTrailingInset: CGFloat = 24
    static let bannerHeight: CGFloat = 500

    struct Metrics {
        let contentLeadingInset: CGFloat
        let contentTrailingInset: CGFloat
        let bannerHeight: CGFloat
        let posterWidth: CGFloat
        let posterHeight: CGFloat
        let watchingWidth: CGFloat
        let watchingHeight: CGFloat
        let gridMinimumWidth: CGFloat
        let gridMaximumWidth: CGFloat
        let gridHorizontalSpacing: CGFloat
        let gridVerticalSpacing: CGFloat
        let detailHorizontalPadding: CGFloat

        static let mac = Metrics(
            contentLeadingInset: 24,
            contentTrailingInset: 24,
            bannerHeight: 500,
            posterWidth: 144,
            posterHeight: 216,
            watchingWidth: 252,
            watchingHeight: 142,
            gridMinimumWidth: 160,
            gridMaximumWidth: 220,
            gridHorizontalSpacing: 14,
            gridVerticalSpacing: 20,
            detailHorizontalPadding: 72
        )

        static let iPhone = Metrics(
            contentLeadingInset: 16,
            contentTrailingInset: 16,
            bannerHeight: 420,
            posterWidth: 118,
            posterHeight: 177,
            watchingWidth: 220,
            watchingHeight: 124,
            gridMinimumWidth: 88,
            gridMaximumWidth: 140,
            gridHorizontalSpacing: 10,
            gridVerticalSpacing: 16,
            detailHorizontalPadding: 16
        )
    }

    static var current: Metrics {
        #if os(iOS)
        return .iPhone
        #else
        return .mac
        #endif
    }

    static var posterGridColumns: [GridItem] {
        #if os(iOS)
        return Array(
            repeating: GridItem(
                .flexible(minimum: current.gridMinimumWidth, maximum: current.gridMaximumWidth),
                spacing: current.gridHorizontalSpacing
            ),
            count: 3
        )
        #else
        return [
            GridItem(
                .adaptive(minimum: current.gridMinimumWidth, maximum: current.gridMaximumWidth),
                spacing: current.gridHorizontalSpacing
            )
        ]
        #endif
    }
}

struct FeaturedBannerArtwork: Equatable {
    let id: CatalogItem.ID
    let imageName: String?
    let posterURL: URL?
    let backgroundURL: URL?
    let fallbackBackgroundURL: URL?

    init(item: CatalogItem) {
        self.id = item.id
        self.imageName = item.imageName
        self.posterURL = item.posterURL
        self.backgroundURL = item.homeBannerBackgroundURL
        self.fallbackBackgroundURL = item.backgroundURL
    }
}

@MainActor
final class HomeBannerScrollStore: ObservableObject {
    static let shared = HomeBannerScrollStore()

    @Published var backgroundOffset: CGFloat = 0
}

@MainActor
final class HomeBannerArtworkStore: ObservableObject {
    static let shared = HomeBannerArtworkStore()

    @Published var artwork: FeaturedBannerArtwork?
}

struct SidebarItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let systemImage: String
}

struct SidebarView<DetailContent: View>: View {
    @State private var selection: SidebarItem? = items.first(where: { $0.title == "Home" })
    @ObservedObject private var bannerArtworkStore = HomeBannerArtworkStore.shared
    @ObservedObject private var homeBannerScrollStore = HomeBannerScrollStore.shared
    @ObservedObject private var playbackStore = StreamPlaybackStore.shared
    let detailContent: (SidebarItem?) -> DetailContent

    init(@ViewBuilder detailContent: @escaping (SidebarItem?) -> DetailContent) {
        self.detailContent = detailContent
    }

    var body: some View {
        GeometryReader { windowGeometry in
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()

                if selection?.title == "Home", let artwork = bannerArtworkStore.artwork {
                    RootFeaturedBanner(artwork: artwork)
                        .id(artwork.id)
                        .frame(width: windowGeometry.size.width, height: OrzenLayout.bannerHeight)
                        .offset(y: homeBannerScrollStore.backgroundOffset)
                        .ignoresSafeArea(.container, edges: [.top, .leading, .trailing])
                }

                NavigationSplitView {
                    List(selection: $selection) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            Button {
                                select(item)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: item.systemImage)
                                        .foregroundColor(.gray)
                                        .frame(width: 20)

                                    Text(item.title)
                                        .foregroundColor(.primary)

                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(sidebarShortcut(for: index), modifiers: .command)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 10)
                            .background {
                                if selection == item {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.1))
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .background(.black.opacity(0.4))
                    .navigationSplitViewColumnWidth(
                        min: OrzenLayout.sidebarDefaultWidth,
                        ideal: OrzenLayout.sidebarDefaultWidth,
                        max: 320
                    )
                } detail: {
                    ZStack {
                        detailContent(selection)
                    }
                    #if os(macOS)
                    .toolbarBackground(.hidden, for: .windowToolbar)
                    #endif
                }

                if let playbackRequest = playbackStore.request {
                    StreamPlayerView(
                        request: playbackRequest,
                        onBack: {
                            withAnimation(.easeInOut(duration: 0.28)) {
                                playbackStore.request = nil
                            }
                        }
                    )
                    .id(playbackRequest.id)
                    .zIndex(10)
                    .transition(.opacity)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 500)
        .toolbar(playbackStore.request == nil ? .visible : .hidden, for: .windowToolbar)
        #endif
    }

    private func select(_ item: SidebarItem) {
        withAnimation {
            selection = item
        }
    }

    private func sidebarShortcut(for index: Int) -> KeyEquivalent {
        KeyEquivalent(Character(String(index + 1)))
    }
}

private struct RootFeaturedBanner: View {
    let artwork: FeaturedBannerArtwork

    var body: some View {
        GeometryReader { geometry in
            let height = OrzenLayout.bannerHeight + geometry.safeAreaInsets.top

            bannerImage(width: geometry.size.width, height: height)
                .frame(width: geometry.size.width, height: height)
                .clipped()
                .overlay(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.black.opacity(0.02),
                            Color.black.opacity(0.42),
                            Color.black
                        ]),
                        startPoint: .center,
                        endPoint: .bottom
                    )
                )
                .offset(y: -geometry.safeAreaInsets.top)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func bannerImage(width: CGFloat, height: CGFloat) -> some View {
        if let backgroundURL = artwork.backgroundURL ?? artwork.posterURL {
            CachedRemoteImage(url: backgroundURL, fallbackURL: artwork.fallbackBackgroundURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
            } placeholder: { _ in
                OrzenArtworkPlaceholder(style: .backdrop)
                    .frame(width: width, height: height)
            }
        } else if let imageName = artwork.imageName {
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
        } else {
            OrzenArtworkPlaceholder(style: .backdrop)
                .frame(width: width, height: height)
        }
    }
}

let items: [SidebarItem] = [
    SidebarItem(title: "Search", systemImage: "magnifyingglass"),
    SidebarItem(title: "Home", systemImage: "house"),
    SidebarItem(title: "Series", systemImage: "tv"),
    SidebarItem(title: "Movies", systemImage: "film"),
    SidebarItem(title: "Collections", systemImage: "square.stack"),
    SidebarItem(title: "Addons", systemImage: "puzzlepiece.extension"),
]

#Preview {
    SidebarView { selectedItem in
        switch selectedItem?.title {
        case "Home":
            Text("Home Content")
        case "Series":
            Text("Series Content")
        case "Movies":
            Text("Movies Content")
        case "Collections":
            Text("Collections Content")
        case "Search":
            Text("Search Content")
        case "Addons":
            Text("Addons Content")
        default:
            Text("Select an item")
        }
    }
}
