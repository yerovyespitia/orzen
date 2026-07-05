import SwiftUI

struct InfoHeroView: View {
    let item: CatalogItem
    var detail = CatalogDetail.empty
    let horizontalPadding: CGFloat
    @ObservedObject private var collectionStore = CollectionStore.shared
    @ObservedObject private var episodeWatchStore = EpisodeWatchStore.shared
    @State private var isListButtonHovered = false
    @State private var isFavoriteButtonHovered = false
    @State private var isWatchedButtonHovered = false
    @State private var isDroppedButtonHovered = false
    @State private var isConfirmingMarkAllWatched = false

    private var collectionActions: CatalogItemCollectionActions {
        CatalogItemCollectionActions(item: item, episodes: detail.episodes)
    }

    var body: some View {
        #if os(iOS)
        mobileBody
        #else
        desktopBody
        #endif
    }

    private var desktopBody: some View {
        HStack(alignment: .top, spacing: 32) {
            posterImage
                .frame(width: 220, height: 320)
                .clipped()
                .cornerRadius(16)
                .shadow(radius: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 16) {
                Text(item.title)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(3)

                Text(item.description)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.top, 8)

                detailPills
                actionButtons
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 116)
        .alert("Mark all episodes as watched?", isPresented: $isConfirmingMarkAllWatched) {
            Button("Cancel", role: .cancel) { }
            Button("Mark All", action: markSeriesWatched)
        } message: {
            Text("This series already has watched episodes. Marking all will mark every episode as watched.")
        }
    }

    private var mobileBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                posterImage
                    .frame(width: 92, height: 138)
                    .clipped()
                    .cornerRadius(10)
                    .shadow(radius: 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 10) {
                    Text(item.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(3)

                    detailPills
                        .frame(maxWidth: .infinity, alignment: .leading)

                    actionButtons
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            ExpandableDescriptionText(text: item.description)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 58)
        .alert("Mark all episodes as watched?", isPresented: $isConfirmingMarkAllWatched) {
            Button("Cancel", role: .cancel) { }
            Button("Mark All", action: markSeriesWatched)
        } message: {
            Text("This series already has watched episodes. Marking all will mark every episode as watched.")
        }
    }

    @ViewBuilder
    private var posterImage: some View {
        if let posterURL = item.posterURL {
            CachedRemoteImage(url: posterURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                posterPlaceholder
            }
        } else if let imageName = item.imageName {
            Image(imageName)
                .resizable()
                .scaledToFill()
        } else {
            posterPlaceholder
        }
    }

    private var posterPlaceholder: some View {
        OrzenArtworkPlaceholder(style: .poster)
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            actionButton(
                systemImage: isAddedToList ? "checkmark" : "text.badge.plus",
                isSelected: isAddedToList,
                isHovered: isListButtonHovered,
                help: listToggleHelp,
                action: collectionActions.togglePlanToWatch
            )
            #if os(macOS)
            .onHover { hovering in
                isListButtonHovered = hovering
            }
            #endif
            .animation(.easeInOut(duration: 0.12), value: isListButtonHovered)

            actionButton(
                systemImage: isFavorite ? "heart.fill" : "heart",
                isSelected: isFavorite,
                isHovered: isFavoriteButtonHovered,
                help: favoriteToggleHelp,
                action: collectionActions.toggleFavorite
            )
            #if os(macOS)
            .onHover { hovering in
                isFavoriteButtonHovered = hovering
            }
            #endif
            .animation(.easeInOut(duration: 0.12), value: isFavoriteButtonHovered)

            actionButton(
                systemImage: isWatched ? "eye.fill" : "eye.slash.fill",
                isSelected: isWatched,
                isHovered: isWatchedButtonHovered,
                help: watchedToggleHelp,
                action: handleWatchedAction
            )
            #if os(macOS)
            .onHover { hovering in
                isWatchedButtonHovered = hovering
            }
            #endif
            .animation(.easeInOut(duration: 0.12), value: isWatchedButtonHovered)

            actionButton(
                systemImage: isDropped ? "archivebox.fill" : "archivebox",
                isSelected: isDropped,
                isHovered: isDroppedButtonHovered,
                help: droppedToggleHelp,
                action: handleDroppedAction
            )
            #if os(macOS)
            .onHover { hovering in
                isDroppedButtonHovered = hovering
            }
            #endif
            .animation(.easeInOut(duration: 0.12), value: isDroppedButtonHovered)
        }
    }

    @ViewBuilder
    private func actionButton(
        systemImage: String,
        isSelected: Bool,
        isHovered: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.14), action)
        } label: {
            if #available(macOS 26, *) {
                actionIcon(systemImage: systemImage, isSelected: isSelected)
                    .background(actionBackground(isSelected: isSelected, isHovered: isHovered))
                    .glassEffect(.regular.interactive(), in: Circle())
            } else {
                actionIcon(systemImage: systemImage, isSelected: isSelected)
                    .background(actionBackground(isSelected: isSelected, isHovered: isHovered))
            }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .help(help)
        .accessibilityLabel(help)
    }

    private func actionBackground(isSelected: Bool, isHovered: Bool) -> some View {
        Circle()
            .fill(actionFillColor(isSelected: isSelected, isHovered: isHovered))
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(isHovered ? 0.18 : 0.08), lineWidth: 1)
            )
    }

    private func actionFillColor(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(isHovered ? 0.34 : 0.26)
        }

        return Color.white.opacity(isHovered ? 0.16 : 0.08)
    }

    private func actionIcon(systemImage: String, isSelected: Bool) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: actionIconSize, weight: .semibold))
            .foregroundColor(.white.opacity(isSelected ? 0.96 : 0.86))
            .frame(width: actionButtonSize, height: actionButtonSize)
    }

    private var actionIconSize: CGFloat {
        #if os(iOS)
        return 18
        #else
        return 16
        #endif
    }

    private var actionButtonSize: CGFloat {
        #if os(iOS)
        return 40
        #else
        return 34
        #endif
    }

    private var listToggleHelp: String {
        collectionActions.listToggleTitle
    }

    private var favoriteToggleHelp: String {
        collectionActions.favoriteToggleTitle
    }

    private var watchedToggleHelp: String {
        collectionActions.watchedToggleTitle
    }

    private var droppedToggleHelp: String {
        collectionActions.droppedToggleTitle
    }

    private var isAddedToList: Bool {
        collectionActions.isAddedToList
    }

    private var isFavorite: Bool {
        collectionActions.isFavorite
    }

    private var isWatched: Bool {
        collectionActions.isWatched
    }

    private var isDropped: Bool {
        collectionActions.isDropped
    }

    private func handleWatchedAction() {
        if case .confirmMarkAll = collectionActions.applyWatchedAction() {
            isConfirmingMarkAllWatched = true
        }
    }

    private func markSeriesWatched() {
        collectionActions.markSeriesWatched(episodes: detail.episodes)
    }

    private func handleDroppedAction() {
        collectionActions.applyDroppedAction()
    }

    @ViewBuilder
    private var detailPills: some View {
        #if os(iOS)
        ScrollView(.horizontal, showsIndicators: false) {
            detailPillContent
        }
        #else
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 10) {
                detailPillContent
            }
        } else {
            detailPillContent
        }
        #endif
    }

    private var detailPillContent: some View {
        HStack(spacing: 10) {
            ForEach(details, id: \.self) { detail in
                detailPill(detail)
            }
        }
    }

    @ViewBuilder
    private func detailPill(_ detail: String) -> some View {
        if #available(macOS 26, *) {
            detailPillText(detail)
                .glassEffect(.regular.tint(Color.white.opacity(0.03)), in: Capsule())
        } else {
            detailPillText(detail)
                .background(Color.white.opacity(0.12), in: Capsule())
        }
    }

    private func detailPillText(_ detail: String) -> some View {
        Text(detail)
            .font(detailPillFont)
            .fontWeight(.medium)
            .foregroundColor(.white.opacity(0.86))
            .padding(.horizontal, detailPillHorizontalPadding)
            .padding(.vertical, detailPillVerticalPadding)
    }

    private var detailPillFont: Font {
        #if os(iOS)
        return .caption
        #else
        return .callout
        #endif
    }

    private var detailPillHorizontalPadding: CGFloat {
        #if os(iOS)
        return 10
        #else
        return 12
        #endif
    }

    private var detailPillVerticalPadding: CGFloat {
        #if os(iOS)
        return 5
        #else
        return 6
        #endif
    }

    private var details: [String] {
        [
            item.displayYear,
            item.runtime,
            item.imdbRating.map { "IMDb \($0)" },
            item.genres.first
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
    }
}
