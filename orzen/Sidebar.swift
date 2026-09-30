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
#if os(macOS)
    @State private var macDownloadsExpanded = false
#endif
    @ObservedObject private var bannerArtworkStore = HomeBannerArtworkStore.shared
    @ObservedObject private var homeBannerScrollStore = HomeBannerScrollStore.shared
    @ObservedObject private var playbackStore = StreamPlaybackStore.shared
    @AppStorage(LocalMediaModePreference.storageKey) private var localMediaModeEnabled = false
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
                    VStack(spacing: 0) {
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

                        #if os(macOS)
                        if localMediaModeEnabled {
                            MacDownloadActivityView(isExpanded: $macDownloadsExpanded)
                        }
                        #endif
                    }
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
                    .overlay {
                        if macDownloadsExpanded {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        macDownloadsExpanded = false
                                    }
                                }
                        }
                    }
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
            #if os(macOS)
            macDownloadsExpanded = false
            #endif
        }
    }

    private func sidebarShortcut(for index: Int) -> KeyEquivalent {
        KeyEquivalent(Character(String(index + 1)))
    }
}

private struct DownloadArcIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                indicator(rotation: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    indicator(rotation: rotation(at: timeline.date))
                }
            }
        }
        .frame(width: 22, height: 22)
        .fixedSize()
        .accessibilityLabel("Downloading")
    }

    private func rotation(at date: Date) -> Double {
        (date.timeIntervalSinceReferenceDate * 400).truncatingRemainder(dividingBy: 360)
    }

    private func indicator(rotation: Double) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 2.5

            var track = Path()
            track.addEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.stroke(track, with: .color(.white.opacity(0.16)), lineWidth: 2.5)

            var arc = Path()
            arc.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(rotation),
                endAngle: .degrees(rotation + 180),
                clockwise: false
            )
            context.stroke(
                arc,
                with: .color(.white),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
        }
    }
}

#if os(macOS)
private struct MacDownloadActivityView: View {
    @ObservedObject private var library = LocalMediaLibraryStore.shared
    @Binding private var expanded: Bool
    @State private var observedIDs = Set<UUID>()
    @State private var dismissedCompletion = false

    init(isExpanded: Binding<Bool>) {
        self._expanded = isExpanded
    }

    private var active: [LocalMediaVersion] {
        library.versions.filter { $0.status == .queued || $0.status == .downloading || $0.status == .paused }
    }

    private var observedVersions: [LocalMediaVersion] {
        library.versions.filter { observedIDs.contains($0.id) }
    }

    private var isComplete: Bool {
        !observedVersions.isEmpty && active.isEmpty && observedVersions.allSatisfy { $0.status == .completed }
    }

    var body: some View {
        Group {
            if !active.isEmpty {
                activityPanel
            } else if isComplete && !dismissedCompletion {
                completionPanel
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .onAppear { observeCurrentDownloads() }
        .onChange(of: library.versions) { _, _ in
            observeCurrentDownloads()
        }
    }

    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(active) { version in
                        downloadRow(version)
                            .padding(.vertical, 2)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }

            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    DownloadArcIndicator()
                        .frame(width: 22, height: 22)
                    Text(active.count == 1 ? "Downloading" : "Downloading \(active.count)")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .foregroundStyle(.primary)
    }

    private var completionPanel: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 20)
            Text("Completed")
                .font(.callout.weight(.medium))
            Spacer()
            Button {
                dismissedCompletion = true
                observedIDs.removeAll()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(.primary)
    }

    private func downloadRow(_ version: LocalMediaVersion) -> some View {
        HStack(spacing: 7) {
            Image(systemName: version.status == .paused ? "pause.circle" : "arrow.down.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(version.torrentTitle)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let progress = version.progress {
                Text(progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 4)
    }

    private func observeCurrentDownloads() {
        let currentActiveIDs = Set(active.map(\.id))
        if !currentActiveIDs.isEmpty {
            observedIDs.formUnion(currentActiveIDs)
            dismissedCompletion = false
        }
    }
}
#endif

#if os(iOS)
struct HomeDownloadActivityBanner: View {
    @ObservedObject private var client = RemoteLocalMediaClient.shared
    @AppStorage(LocalMediaModePreference.storageKey) private var localMediaModeEnabled = false
    @Binding private var expanded: Bool
    @State private var versions: [LocalMediaVersion] = []
    @State private var startedIDs = Set<UUID>()
    @State private var showingCompletion = false

    init(isExpanded: Binding<Bool>) {
        self._expanded = isExpanded
    }

    private var active: [LocalMediaVersion] {
        versions.filter { $0.status == .queued || $0.status == .downloading || $0.status == .paused }
    }

    var body: some View {
        Group {
            if localMediaModeEnabled && (!active.isEmpty || showingCompletion) {
                ZStack(alignment: .topTrailing) {
                    if expanded {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(showingCompletion ? "Downloads completed" : "Downloads")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)

                            if !showingCompletion {
                                ForEach(active) { version in
                                    HStack(spacing: 7) {
                                        Image(systemName: "arrow.down.circle").font(.caption)
                                        Text(version.torrentTitle).lineLimit(1)
                                        Spacer(minLength: 8)
                                        if let progress = version.progress {
                                            Text(progress.formatted(.percent.precision(.fractionLength(0))))
                                                .font(.caption.monospacedDigit())
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.9))
                                }
                            }
                        }
                        .padding(12)
                        .frame(width: 250, alignment: .leading)
                        .modifier(DownloadListGlassSurface())
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 5)
                        .padding(.top, 58)
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            ZStack {
                                Circle()
                                    .fill(.clear)
                                    .frame(width: 50, height: 50)
                                    .modifier(DownloadGlassSurface())

                                if showingCompletion {
                                    Image(systemName: "checkmark")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(.green)
                                } else {
                                    DownloadArcIndicator()
                                }

                            }

                            if active.count > 1 && !showingCompletion {
                                Text("\(active.count)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(.blue, in: Circle())
                                    .offset(x: 2, y: -2)
                            }
                        }
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task(id: localMediaModeEnabled) {
            guard localMediaModeEnabled else { return }
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .onAppear {
            guard localMediaModeEnabled else { return }
            Task { await refresh() }
        }
        .onChange(of: client.isPaired) { _, isPaired in
            guard isPaired else { return }
            Task { await refresh() }
        }
    }

    private func refresh() async {
        guard client.isPaired else { return }
        guard let latest = try? await client.versions() else { return }
        versions = latest
        let activeIDs = Set(active.map(\.id))
        if !activeIDs.isEmpty {
            startedIDs.formUnion(activeIDs)
            showingCompletion = false
        } else if !startedIDs.isEmpty,
                  latest.filter({ startedIDs.contains($0.id) }).allSatisfy({ $0.status == .completed }) {
            showingCompletion = true
            expanded = false
            let ids = startedIDs
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                if startedIDs == ids { showingCompletion = false; startedIDs.removeAll() }
            }
        }
    }
}

private struct DownloadGlassSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.22), lineWidth: 1)
                }
        }
    }
}

private struct DownloadListGlassSurface: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(.white.opacity(0.2), lineWidth: 1)
                }
        }
    }
}
#endif

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
    SidebarItem(title: "Settings", systemImage: "gearshape"),
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
        case "Settings":
            Text("Settings Content")
        default:
            Text("Select an item")
        }
    }
}
