import SwiftUI

struct FeaturedCarouselPage: View {
    let item: CatalogItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            background

            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(radius: 8)
                    .lineLimit(2)

                Text(metadata)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.86))
                    .lineLimit(1)
            }
            .padding(.leading, OrzenLayout.current.contentLeadingInset)
            .padding(.trailing, OrzenLayout.current.contentTrailingInset)
            .padding(.bottom, bottomPadding)
        }
    }

    @ViewBuilder
    private var background: some View {
        #if os(iOS)
        GeometryReader { geometry in
            bannerImage(width: geometry.size.width, height: geometry.size.height)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .overlay(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.black.opacity(0.04),
                            Color.black.opacity(0.46),
                            Color.black
                        ]),
                        startPoint: .center,
                        endPoint: .bottom
                    )
                )
                .homeStretchyHeader()
        }
        #else
        Color.clear
        #endif
    }

    @ViewBuilder
    private func bannerImage(width: CGFloat, height: CGFloat) -> some View {
        if let backgroundURL = item.backgroundURL ?? item.posterURL {
            CachedRemoteImage(url: backgroundURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
            } placeholder: {
                OrzenArtworkPlaceholder(style: .backdrop)
                    .frame(width: width, height: height)
            }
        } else if let imageName = item.imageName {
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
        } else {
            OrzenArtworkPlaceholder(style: .backdrop)
                .frame(width: width, height: height)
        }
    }

    private var titleSize: CGFloat {
        #if os(iOS)
        return 30
        #else
        return 40
        #endif
    }

    private var bottomPadding: CGFloat {
        #if os(iOS)
        return 76
        #else
        return 92
        #endif
    }

    private var metadata: String {
        [
            item.displayYear,
            item.genres.first,
            item.runtime
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: " • ")
    }
}

#if os(iOS)
private extension View {
    func homeStretchyHeader() -> some View {
        visualEffect { effect, geometry in
            let currentHeight = geometry.size.height
            let scrollOffset = geometry.frame(in: .scrollView).minY
            let positiveOffset = max(0, scrollOffset)
            let stretchedHeight = currentHeight + positiveOffset
            let scaleFactor = stretchedHeight / currentHeight

            return effect.scaleEffect(
                x: scaleFactor,
                y: scaleFactor,
                anchor: .bottom
            )
        }
    }
}
#endif
