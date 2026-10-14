import SwiftUI

struct CatalogPosterCard: View {
    let item: CatalogItem
    var showsDroppedContextAction = false
    var onViewDetails: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                poster
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .center, spacing: 4) {
                        Text(item.title)
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(8)
                            .shadow(radius: 4)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        if !metadata.isEmpty {
                            Text(metadata)
                                .font(.caption)
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                    }
                    .padding(8)
                }
                .opacity(isHovered ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipped()
        .contentShape(Rectangle())
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .modifier(CatalogDownloadIndicator(item: item))
        .animation(.easeInOut(duration: 0.2), value: isHovered)
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
    private var poster: some View {
        if let posterURL = item.posterURL {
            CachedRemoteImage(url: posterURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: { _ in
                placeholder
            }
        } else if let imageName = item.imageName {
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        OrzenArtworkPlaceholder(style: .poster)
    }

    private var metadata: String {
        [item.displayYear, item.genres.first, item.runtime]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " • ")
    }
}

struct CatalogDownloadIndicator: ViewModifier {
    let item: CatalogItem
    @ObservedObject private var library = LocalMediaLibraryStore.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if library.hasDownload(for: item) {
                    CatalogDownloadBadge()
                        .padding(8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(item.title)
            .accessibilityValue(library.hasDownload(for: item) ? downloadDescription : "")
            .help(library.hasDownload(for: item) ? downloadDescription : item.title)
    }

    private var downloadDescription: String {
        item.cinemetaType == .series ? "Downloaded episodes available" : "Downloaded"
    }
}

private struct CatalogDownloadBadge: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        surface
            .colorScheme(.dark)
    }

    private var symbol: some View {
        Image(systemName: "arrow.down.to.line")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
    }

    @ViewBuilder
    private var surface: some View {
        if reduceTransparency {
            symbol.background(Color.black.opacity(0.85), in: Circle())
        } else if #available(iOS 26, macOS 26, *) {
            symbol.glassEffect(.regular, in: Circle())
        } else {
            symbol
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.16), lineWidth: 1)
                }
        }
    }
}
