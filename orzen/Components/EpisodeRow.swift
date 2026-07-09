import SwiftUI

struct EpisodeRow: View {
    let episode: CatalogEpisode
    let bannerURL: URL?
    var isSelected = false
    var isWatched = false
    var isCurrent = false

    var body: some View {
        HStack(alignment: .top, spacing: rowSpacing) {
            thumbnail
                .frame(width: thumbnailWidth, height: thumbnailHeight)
                .clipShape(EpisodeRowStyle.cardShape)
                .overlay {
                    EpisodeRowStyle.cardShape
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    if isCurrent || isWatched {
                        statusBadges
                            .padding(.top, 12)
                            .padding(.leading, 12)
                    }
                }

            VStack(alignment: .leading, spacing: 8) {
                Text(episode.displayTitle)
                    .font(titleFont)
                    .foregroundColor(.white)
                    .lineLimit(2)

                if !episode.metadata.isEmpty {
                    Text(episode.metadata.joined(separator: " • "))
                        .font(metadataFont)
                        .foregroundColor(.white.opacity(0.62))
                        .lineLimit(1)
                }

                Text(episode.description ?? "No description available.")
                    .font(descriptionFont)
                    .foregroundColor(.white.opacity(0.78))
                    .lineLimit(descriptionLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(rowPadding)
        .frame(minHeight: minimumHeight, alignment: .top)
        .rowBackground(isSelected: isSelected)
    }

    private var thumbnailWidth: CGFloat {
        #if os(iOS)
        return 104
        #else
        return 190
        #endif
    }

    private var thumbnailHeight: CGFloat {
        #if os(iOS)
        return 68
        #else
        return 123
        #endif
    }

    private var rowSpacing: CGFloat {
        #if os(iOS)
        return 10
        #else
        return 16
        #endif
    }

    private var rowPadding: CGFloat {
        #if os(iOS)
        return 10
        #else
        return 12
        #endif
    }

    private var minimumHeight: CGFloat {
        #if os(iOS)
        return 88
        #else
        return 147
        #endif
    }

    private var titleFont: Font {
        #if os(iOS)
        return .subheadline.weight(.semibold)
        #else
        return .headline
        #endif
    }

    private var metadataFont: Font {
        #if os(iOS)
        return .caption2
        #else
        return .caption
        #endif
    }

    private var descriptionFont: Font {
        #if os(iOS)
        return .caption
        #else
        return .callout
        #endif
    }

    private var descriptionLineLimit: Int {
        #if os(iOS)
        return 2
        #else
        return 3
        #endif
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumbnailURL = episode.thumbnailURL {
            CachedRemoteImage(url: thumbnailURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: { isLoading in
                thumbnailPlaceholder(isLoading: isLoading)
            }
        } else {
            thumbnailPlaceholder(isLoading: false)
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
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))

            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .foregroundColor(.black.opacity(0.86))
        .background(Color.white.opacity(0.94), in: Capsule())
        .fixedSize()
        .overlay {
            Capsule()
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
    }

    private func thumbnailPlaceholder(isLoading: Bool) -> some View {
        ZStack {
            if isLoading {
                OrzenArtworkPlaceholder(style: .backdrop)
                Image(systemName: "play.rectangle")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.64))
            } else {
                bannerArtwork

                if bannerURL == nil {
                    Image(systemName: "play.rectangle")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.64))
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
}

private enum EpisodeRowStyle {
    static var cornerRadius: CGFloat {
        #if os(iOS)
        return 10
        #else
        return 14
        #endif
    }
    static let cardShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
}

private extension View {
    @ViewBuilder
    func rowBackground(isSelected: Bool) -> some View {
        let shape = EpisodeRowStyle.cardShape

        if #available(macOS 26, *) {
            self
                .glassEffect(.regular.tint(Color.white.opacity(isSelected ? 0.05 : 0.02)), in: shape)
                .overlay {
                    shape.stroke(isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.04), lineWidth: 1)
                }
        } else {
            self
                .background(Color.white.opacity(isSelected ? 0.1 : 0.045), in: shape)
                .overlay {
                    shape.stroke(isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.04), lineWidth: 1)
                }
        }
    }
}
