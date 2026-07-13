import SwiftUI

struct StreamPlayerEpisodeSidebar: View {
    private static let width: CGFloat = 440
    private static let horizontalPadding: CGFloat = 18
    private static let episodeListTopID = "stream-player-episode-list-top"
    private static let seasonSelectorHeight: CGFloat = 46

    let item: CatalogItem
    let currentEpisodeID: CatalogEpisode.ID?
    let currentSourceID: StreamSource.ID
    let currentTrackSelections: PlaybackTrackSelections
    let onClose: () -> Void

    @ObservedObject private var episodeWatchStore = EpisodeWatchStore.shared
    @ObservedObject private var playbackProgressStore = PlaybackProgressStore.shared
    @StateObject private var viewModel: InfoViewModel
    @State private var didSelectInitialEpisode = false
    @State private var hoveredChromeButton: SidebarChromeButton?

    init(
        item: CatalogItem,
        currentEpisodeID: CatalogEpisode.ID?,
        currentSourceID: StreamSource.ID,
        currentTrackSelections: PlaybackTrackSelections,
        onClose: @escaping () -> Void
    ) {
        self.item = item
        self.currentEpisodeID = currentEpisodeID
        self.currentSourceID = currentSourceID
        self.currentTrackSelections = currentTrackSelections
        self.onClose = onClose
        _viewModel = StateObject(wrappedValue: InfoViewModel(item: item))
    }

    var body: some View {
        content
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            mainContent
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, 20)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(sidebarBackground)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
        }
        .task(id: item.id) {
            await viewModel.loadDetail()
            selectInitialEpisodeIfNeeded()
        }
        .onChange(of: currentEpisodeID) { _, _ in
            didSelectInitialEpisode = false
            selectInitialEpisodeIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.selectedEpisode == nil ? "Episodes" : "Sources")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)

                Text(item.title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.62))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if viewModel.selectedEpisode != nil {
                chromeButton(
                    id: .back,
                    systemName: "chevron.left",
                    help: "Back to episodes",
                    action: showEpisodes
                )
            }

            #if os(macOS)
            chromeButton(
                id: .close,
                systemName: "xmark",
                help: "Close episodes",
                action: onClose
            )
            #endif
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.isLoadingDetail && viewModel.detail.episodes.isEmpty {
            loadingView
        } else if viewModel.detail.episodes.isEmpty {
            emptyView
        } else if viewModel.selectedEpisode != nil {
            sourcesList
        } else {
            episodesContent
        }
    }

    private var episodesContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            seasonSelector
            episodeList
        }
    }

    private var loadingView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(.white)

            Text("Loading episodes")
                .font(.callout.weight(.medium))
                .foregroundColor(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var emptyView: some View {
        DetailUnavailableView(
            systemImage: "list.bullet.rectangle",
            title: "No episode details",
            message: viewModel.detailErrorMessage ?? "Cinemeta did not return episode metadata for this series."
        )
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private var seasonSelector: some View {
        let viewportWidth = Self.width - (Self.horizontalPadding * 2)

        return ZStack(alignment: .leading) {
            Color.clear

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.availableSeasons, id: \.self) { season in
                            SeasonButton(
                                season: season,
                                isSelected: viewModel.selectedSeason == season,
                                action: {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        viewModel.selectedSeason = season
                                    }
                                }
                            )
                            .id(season)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                }
                .frame(width: viewportWidth, height: Self.seasonSelectorHeight, alignment: .leading)
                .clipShape(Rectangle())
                .onChange(of: viewModel.selectedSeason) { _, season in
                    scrollToSelectedSeasonButton(season, with: scrollProxy)
                }
                .onChange(of: viewModel.availableSeasons) { _, _ in
                    scrollToSelectedSeasonButton(viewModel.selectedSeason, with: scrollProxy)
                }
                .onAppear {
                    scrollToSelectedSeasonButton(viewModel.selectedSeason, with: scrollProxy)
                }
            }
        }
        .frame(width: viewportWidth, height: Self.seasonSelectorHeight, alignment: .leading)
    }

    private var episodeList: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                Color.clear
                    .frame(height: 0)
                    .id(Self.episodeListTopID)

                LazyVStack(spacing: 10) {
                    ForEach(viewModel.selectedSeasonEpisodes) { episode in
                        episodeButton(episode)
                            .id(episode.id)
                    }
                }
                .padding(.bottom, 14)
            }
            .onChange(of: viewModel.selectedEpisodeID) { _, episodeID in
                guard let episodeID else { return }
                scrollProxy.scrollTo(episodeID, anchor: .center)
            }
            .onChange(of: viewModel.selectedSeason) { _, _ in
                scrollToSelectedSeasonPosition(with: scrollProxy)
            }
            .onChange(of: viewModel.selectedSeasonEpisodes.map(\.id)) { _, _ in
                scrollToSelectedSeasonPosition(with: scrollProxy)
            }
            .onChange(of: viewModel.hasLoadedDetail) { _, hasLoadedDetail in
                guard hasLoadedDetail else { return }
                scrollToCurrentEpisode(with: scrollProxy)
            }
            .onChange(of: currentEpisodeID) { _, _ in
                scrollToCurrentEpisode(with: scrollProxy)
            }
            .onAppear {
                scrollToCurrentEpisode(with: scrollProxy)
            }
        }
    }

    private func episodeButton(_ episode: CatalogEpisode) -> some View {
        Button {
            selectEpisode(episode)
        } label: {
            StreamPlayerEpisodeSidebarRow(
                episode: episode,
                bannerURL: item.backgroundURL,
                isSelected: viewModel.selectedEpisodeID == episode.id,
                isCurrent: currentEpisodeID == episode.id,
                isWatched: episodeWatchStore.isWatched(episode)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                let didMarkWatched = episodeWatchStore.toggleWatched(
                    episode,
                    in: item,
                    episodes: viewModel.detail.episodes
                )
                viewModel.syncSeriesCollectionState()

                guard didMarkWatched else { return }
                Task {
                    await playbackProgressStore.advanceWatchingProgressIfNeeded(
                        afterMarkingWatched: episode,
                        in: item,
                        trackSelections: currentTrackSelections
                    )
                }
            } label: {
                Label(
                    episodeWatchStore.isWatched(episode) ? "Remove from Watched" : "Mark as Watched",
                    systemImage: episodeWatchStore.isWatched(episode) ? "eye.slash.fill" : "eye.fill"
                )
            }

            Button {
                episodeWatchStore.markEpisodesBeforeWatched(
                    episode,
                    in: item,
                    episodes: viewModel.detail.episodes
                )
                viewModel.syncSeriesCollectionState()
            } label: {
                Label("Mark Previous Episodes as Watched", systemImage: "eye.fill")
            }
            .disabled(
                !episodeWatchStore.hasEpisodes(
                    before: episode,
                    in: viewModel.detail.episodes
                )
            )
        }
    }

    @ViewBuilder
    private var sourcesList: some View {
        if viewModel.isLoadingSources {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)

                Text("Loading sources")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.66))
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        } else if !viewModel.visibleSources.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                selectedEpisodeSummary
                sourceFilter

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.visibleSources) { source in
                            Button {
                                viewModel.playSource(
                                    source,
                                    initialTrackSelections: currentTrackSelections,
                                    attemptedSourceIDs: [currentSourceID]
                                )
                                onClose()
                            } label: {
                                StreamPlayerEpisodeSidebarSourceRow(
                                    source: source,
                                    isCurrent: source.id == currentSourceID
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 14)
                }
            }
        } else if let sourceErrorMessage = viewModel.sourceErrorMessage {
            sidebarMessage(systemImage: "wifi.exclamationmark", message: sourceErrorMessage)
        } else if viewModel.hasLoadedSources {
            sidebarMessage(systemImage: "tray", message: "No sources found for this episode.")
        }
    }

    @ViewBuilder
    private var sourceFilter: some View {
        if !viewModel.sourceFilterCategories.isEmpty {
            SourceFilterPicker(
                selection: $viewModel.selectedSourceFilter,
                categories: viewModel.sourceFilterCategories
            )
        }
    }

    @ViewBuilder
    private var selectedEpisodeSummary: some View {
        if let episode = viewModel.selectedEpisode {
            VStack(alignment: .leading, spacing: 6) {
                Text(episode.displayTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                if !episode.metadata.isEmpty {
                    Text(episode.metadata.joined(separator: " • "))
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white.opacity(0.58))
                        .lineLimit(1)
                }
            }
            .padding(.bottom, 2)
        }
    }

    private var sidebarBackground: some View {
        Color.black
            .ignoresSafeArea()
    }

    private func sidebarMessage(systemImage: String, message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))

            Text(message)
                .font(.caption)
                .lineLimit(3)
        }
        .foregroundColor(.white.opacity(0.64))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func chromeButton(
        id: SidebarChromeButton,
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        let buttonSize: CGFloat = 44
        let iconSize: CGFloat = 16

        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(.white.opacity(0.88))
                .frame(width: buttonSize, height: buttonSize)
                .background(chromeButtonBackground(id))
                .modifier(SidebarGlassButtonModifier(shape: Circle()))
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .onHover { hovering in
            hoveredChromeButton = hovering ? id : nil
        }
        .animation(.easeInOut(duration: 0.12), value: hoveredChromeButton)
        .help(help)
        .accessibilityLabel(help)
    }

    private func chromeButtonBackground(_ id: SidebarChromeButton) -> some View {
        let isHovered = hoveredChromeButton == id

        return Circle()
            .fill(Color.white.opacity(isHovered ? 0.16 : 0.08))
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(isHovered ? 0.14 : 0.06), lineWidth: 1)
            }
    }

    private func selectInitialEpisodeIfNeeded() {
        guard !didSelectInitialEpisode,
              viewModel.hasLoadedDetail,
              let currentEpisodeID,
              let episode = viewModel.detail.episodes.first(where: { $0.id == currentEpisodeID }) else {
            return
        }

        didSelectInitialEpisode = true
        viewModel.selectedSeason = episode.season ?? 1
    }

    private func scrollToCurrentEpisode(with scrollProxy: ScrollViewProxy) {
        guard let currentEpisode = currentEpisode else { return }

        Task { @MainActor in
            viewModel.selectedSeason = currentEpisode.season ?? 1
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.easeInOut(duration: 0.32)) {
                scrollProxy.scrollTo(currentEpisode.id, anchor: .top)
            }
        }
    }

    private func scrollToSelectedSeasonPosition(with scrollProxy: ScrollViewProxy) {
        if currentEpisode?.season == viewModel.selectedSeason {
            scrollToCurrentEpisode(with: scrollProxy)
        } else {
            scrollToEpisodeListTop(with: scrollProxy)
        }
    }

    private func scrollToEpisodeListTop(with scrollProxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.easeInOut(duration: 0.22)) {
                scrollProxy.scrollTo(Self.episodeListTopID, anchor: .top)
            }
        }
    }

    private var currentEpisode: CatalogEpisode? {
        guard let currentEpisodeID else { return nil }
        return viewModel.detail.episodes.first { $0.id == currentEpisodeID }
    }

    private func scrollToSelectedSeasonButton(
        _ season: Int,
        with scrollProxy: ScrollViewProxy
    ) {
        guard viewModel.availableSeasons.contains(season) else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.easeInOut(duration: 0.18)) {
                scrollProxy.scrollTo(season, anchor: .leading)
            }
        }
    }

    private func showEpisodes() {
        viewModel.showEpisodes()
    }

    private func selectEpisode(_ episode: CatalogEpisode) {
        viewModel.selectEpisode(episode)
    }
}

private enum SidebarChromeButton {
    case back
    case close
}

struct SidebarGlassButtonModifier<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.clear.interactive(), in: shape)
        } else {
            content
        }
    }
}
