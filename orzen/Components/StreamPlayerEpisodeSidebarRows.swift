import SwiftUI

struct StreamPlayerEpisodeSidebarRow: View {
    let episode: CatalogEpisode
    let bannerURL: URL?
    let isSelected: Bool
    let isCurrent: Bool
    let isWatched: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
                .frame(width: 76, height: 48)
                .clipShape(rowShape)
                .overlay {
                    rowShape.stroke(Color.white.opacity(0.08), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(episode.displayTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text(episode.metadata.joined(separator: " • "))
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.white.opacity(0.56))
                    .lineLimit(1)

                if isCurrent || isWatched {
                    statusBadges
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(isSelected ? 0.7 : 0.32))
                .padding(.top, 3)
        }
        .padding(10)
        .sidebarEpisodeRowBackground(
            isSelected: isSelected,
            isHovered: isHovered,
            shape: rowShape
        )
        .contentShape(rowShape)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumbnailURL = episode.thumbnailURL {
            CachedRemoteImage(url: thumbnailURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: { isLoading in
                placeholder(isLoading: isLoading)
            }
        } else {
            placeholder(isLoading: false)
        }
    }

    private func placeholder(isLoading: Bool) -> some View {
        ZStack {
            if isLoading {
                OrzenArtworkPlaceholder(style: .backdrop)
                Image(systemName: "play.rectangle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.56))
            } else {
                bannerArtwork

                if bannerURL == nil {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.56))
                }
            }
        }
    }

    @ViewBuilder
    private var bannerArtwork: some View {
        if let bannerURL {
            CachedRemoteImage(url: bannerURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: { _ in
                OrzenArtworkPlaceholder(style: .backdrop)
            }
        } else {
            OrzenArtworkPlaceholder(style: .backdrop)
        }
    }

    private var statusBadges: some View {
        HStack(spacing: 6) {
            if isCurrent {
                badge(title: "Now", systemImage: "play.fill")
            }

            if isWatched {
                badge(title: "Watched", systemImage: "eye.fill")
            }
        }
    }

    private func badge(title: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))

            Text(title)
                .font(.caption2.weight(.bold))
        }
        .foregroundColor(.black.opacity(0.82))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.9), in: Capsule())
    }

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }
}

struct StreamPlayerEpisodeSidebarSourceRow: View {
    let source: StreamSource
    let isCurrent: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: sourceIconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.68))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(source.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.94))
                    .lineLimit(2)

                Text(source.metadata.joined(separator: " • "))
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.white.opacity(0.54))
                    .lineLimit(1)

                compatibilityMessage
                compatibilityDetail
            }

            Spacer(minLength: 0)

            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.82))
                    .padding(.top, 3)
            }
        }
        .padding(10)
        .background(rowBackground, in: rowShape)
        .modifier(SidebarGlassButtonModifier(shape: rowShape))
        .overlay {
            rowShape.stroke(rowStroke, lineWidth: 1)
        }
        .contentShape(rowShape)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    private var rowBackground: Color {
        if isCurrent {
            return Color.white.opacity(isHovered ? 0.15 : 0.11)
        }

        return Color.white.opacity(isHovered ? 0.09 : 0.055)
    }

    private var rowStroke: Color {
        if isCurrent {
            return Color.white.opacity(isHovered ? 0.22 : 0.18)
        }

        return Color.white.opacity(isHovered ? 0.11 : 0.05)
    }

    private var sourceIconName: String {
        #if os(iOS)
        switch NativePlaybackCompatibilityResolver.compatibility(for: source) {
        case .unsupported:
            return "exclamationmark.triangle.fill"
        case .unknown:
            return "questionmark.circle.fill"
        case .supported, .likely:
            return "play.circle.fill"
        }
        #else
        return source.playbackURL == nil ? "exclamationmark.triangle.fill" : "play.circle.fill"
        #endif
    }

    @ViewBuilder
    private var compatibilityMessage: some View {
        #if os(iOS)
        let compatibility = NativePlaybackCompatibilityResolver.compatibility(for: source)
        if let title = compatibility.badgeTitle {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.white.opacity(compatibility.canAttemptPlayback ? 0.7 : 0.5))
                .lineLimit(1)
        }
        #endif
    }

    @ViewBuilder
    private var compatibilityDetail: some View {
        #if os(iOS)
        let compatibility = NativePlaybackCompatibilityResolver.compatibility(for: source)
        if !compatibility.canAttemptPlayback,
           let message = compatibility.message {
            Text(message)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.46))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        #endif
    }
}

private extension View {
    @ViewBuilder
    func sidebarEpisodeRowBackground(
        isSelected: Bool,
        isHovered: Bool,
        shape: RoundedRectangle
    ) -> some View {
        let strokeOpacity = isSelected ? 0.18 : (isHovered ? 0.08 : 0.04)

        #if os(iOS)
        if #available(iOS 26, *) {
            self
                .glassEffect(.clear, in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
                }
        } else {
            self
                .background(Color.white.opacity(isSelected ? 0.1 : (isHovered ? 0.065 : 0.045)), in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
                }
        }
        #elseif os(macOS)
        if #available(macOS 26, *) {
            self
                .glassEffect(.clear, in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
                }
        } else {
            self
                .background(Color.white.opacity(isSelected ? 0.1 : (isHovered ? 0.065 : 0.045)), in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
                }
        }
        #else
        self
            .background(Color.white.opacity(isSelected ? 0.1 : (isHovered ? 0.065 : 0.045)), in: shape)
            .overlay {
                shape.stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
            }
        #endif
    }
}
