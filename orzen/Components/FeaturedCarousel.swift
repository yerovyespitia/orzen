import SwiftUI

struct FeaturedCarousel: View {
    let items: [CatalogItem]
    @State private var selectedItemID: CatalogItem.ID?
    @State private var hoveredButtonImage: String?
    @State private var dragTranslation: CGFloat = 0
    
    private let carouselAnimation = Animation.smooth(duration: 0.58, extraBounce: 0)
    private let swipeSettleAnimation = Animation.easeInOut(duration: 0.22)
    private let swipeSettleDuration: TimeInterval = 0.22
    private let swipeThreshold: CGFloat = 48
    #if os(iOS)
    private let interactivePopGestureEdgeWidth: CGFloat = 44
    #endif
    private var metrics: OrzenLayout.Metrics {
        OrzenLayout.current
    }
    
    var body: some View {
        GeometryReader { geometry in
            let pageWidth = geometry.size.width

            ZStack {
                let interactiveOffset = interactivePageOffset(for: pageWidth)

                if let previousItem = adjacentItem(in: -1),
                   interactiveOffset > 0 {
                    carouselPage(for: previousItem, pageWidth: pageWidth)
                        .offset(x: interactiveOffset - pageWidth)
                        .zIndex(1)
                }

                if let nextItem = adjacentItem(in: 1),
                   interactiveOffset < 0 {
                    carouselPage(for: nextItem, pageWidth: pageWidth)
                        .offset(x: interactiveOffset + pageWidth)
                        .zIndex(1)
                }

                if let selectedItem {
                    carouselPage(for: selectedItem, pageWidth: pageWidth)
                        .offset(x: interactiveOffset)
                        .zIndex(2)
                }

                if items.count > 1 {
                    carouselControls(pageWidth: pageWidth)
                        .zIndex(3)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 24, coordinateSpace: .local)
                    .onChanged { value in
                        updateDrag(with: value, pageWidth: pageWidth)
                    }
                    .onEnded { value in
                        handleSwipe(value, pageWidth: pageWidth)
                    }
            )
            .onAppear(perform: selectInitialItemIfNeeded)
            .onChange(of: items.map(\.id)) { _, ids in
                guard selectedItemID.map({ ids.contains($0) }) != true else { return }
                selectedItemID = ids.first
            }
        }
        .frame(height: metrics.bannerHeight)
        .padding(.bottom, 22)
        .preference(
            key: FeaturedBannerArtworkKey.self,
            value: selectedItem.map(FeaturedBannerArtwork.init)
        )
    }
    
    private var selectedItem: CatalogItem? {
        guard let selectedItemID,
              let item = items.first(where: { $0.id == selectedItemID }) else {
            return items.first
        }
        
        return item
    }
    
    private var selectedIndex: Int? {
        guard let selectedItemID else { return items.indices.first }
        return items.firstIndex { $0.id == selectedItemID }
    }
    
    private var canMoveBackward: Bool {
        guard let selectedIndex else { return false }
        return selectedIndex > items.startIndex
    }
    
    private var canMoveForward: Bool {
        guard let selectedIndex else { return false }
        return selectedIndex < items.index(before: items.endIndex)
    }

    private func adjacentItem(in direction: Int) -> CatalogItem? {
        guard !items.isEmpty else { return nil }

        let currentIndex = selectedIndex ?? items.startIndex
        let adjacentIndex = currentIndex + direction

        guard items.indices.contains(adjacentIndex) else { return nil }
        return items[adjacentIndex]
    }

    private func selectInitialItemIfNeeded() {
        guard selectedItemID == nil else { return }
        selectedItemID = items.first?.id
    }
    
    private func moveSelection(by offset: Int) {
        guard !items.isEmpty else { return }
        
        let currentIndex = selectedIndex ?? items.startIndex
        let proposedIndex = currentIndex + offset
        let clampedIndex = min(max(proposedIndex, items.startIndex), items.index(before: items.endIndex))
        let nextID = items[clampedIndex].id
        
        withAnimation(carouselAnimation) {
            selectedItemID = nextID
        }
    }

    private func updateDrag(with value: DragGesture.Value, pageWidth: CGFloat) {
        #if os(iOS)
        guard !isInteractivePopGesture(value) else { return }
        #endif

        let horizontalMovement = value.translation.width
        let verticalMovement = value.translation.height

        guard abs(horizontalMovement) > abs(verticalMovement) else { return }
        dragTranslation = clampedDragTranslation(horizontalMovement, pageWidth: pageWidth)
    }

    private func interactivePageOffset(for pageWidth: CGFloat) -> CGFloat {
        clampedDragTranslation(dragTranslation, pageWidth: pageWidth)
    }

    private func clampedDragTranslation(_ translation: CGFloat, pageWidth: CGFloat) -> CGFloat {
        let maximumTranslation = pageWidth

        if translation > 0 {
            let translationScale: CGFloat = canMoveBackward ? 1 : 0.18
            return min(translation * translationScale, maximumTranslation)
        }

        if translation < 0 {
            let translationScale: CGFloat = canMoveForward ? 1 : 0.18
            return max(translation * translationScale, -maximumTranslation)
        }

        return 0
    }

    private func handleSwipe(_ value: DragGesture.Value, pageWidth: CGFloat) {
        let horizontalMovement = value.translation.width
        let verticalMovement = value.translation.height

        #if os(iOS)
        guard !isInteractivePopGesture(value) else {
            dragTranslation = 0
            return
        }
        #endif

        guard abs(horizontalMovement) > abs(verticalMovement),
              abs(horizontalMovement) >= swipeThreshold else {
            withAnimation(swipeSettleAnimation) {
                dragTranslation = 0
            }
            return
        }

        let direction = horizontalMovement < 0 ? 1 : -1
        guard let nextItem = adjacentItem(in: direction) else {
            withAnimation(swipeSettleAnimation) {
                dragTranslation = 0
            }
            return
        }

        withAnimation(swipeSettleAnimation) {
            dragTranslation = direction > 0 ? -pageWidth : pageWidth
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + swipeSettleDuration) {
            var transaction = Transaction()
            transaction.disablesAnimations = true

            withTransaction(transaction) {
                selectedItemID = nextItem.id
                dragTranslation = 0
            }
        }
    }

    #if os(iOS)
    private func isInteractivePopGesture(_ value: DragGesture.Value) -> Bool {
        value.startLocation.x <= interactivePopGestureEdgeWidth && value.translation.width > 0
    }
    #endif
    
    @ViewBuilder
    private func carouselButton(
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if #available(macOS 26, *) {
            Button(action: action) {
                carouselButtonIcon(systemImage, isEnabled: isEnabled)
                    .background(carouselButtonBackground(systemImage: systemImage, isEnabled: isEnabled))
                    .glassEffect(isEnabled ? .regular.interactive() : .regular, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.18)
            .contentShape(Circle())
            .onHover { hovering in
                hoveredButtonImage = hovering && isEnabled ? systemImage : nil
            }
            .animation(.easeInOut(duration: 0.12), value: hoveredButtonImage)
            .accessibilityLabel(systemImage == "chevron.left" ? "Previous featured title" : "Next featured title")
        } else {
            Button(action: action) {
                carouselButtonIcon(systemImage, isEnabled: isEnabled)
                    .background(carouselButtonBackground(systemImage: systemImage, isEnabled: isEnabled))
                    .shadow(color: .black.opacity(isEnabled ? 0.35 : 0.12), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.18)
            .contentShape(Circle())
            .onHover { hovering in
                hoveredButtonImage = hovering && isEnabled ? systemImage : nil
            }
            .animation(.easeInOut(duration: 0.12), value: hoveredButtonImage)
            .accessibilityLabel(systemImage == "chevron.left" ? "Previous featured title" : "Next featured title")
        }
    }

    private func carouselButtonBackground(systemImage: String, isEnabled: Bool) -> some View {
        let isHovered = hoveredButtonImage == systemImage && isEnabled

        return Circle()
            .fill(Color.white.opacity(isHovered ? 0.16 : 0.08))
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(isHovered ? 0.14 : 0.06), lineWidth: 1)
            )
    }

    private func carouselButtonIcon(_ systemImage: String, isEnabled: Bool) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.white.opacity(isEnabled ? 1 : 0.42))
            .frame(width: 44, height: 44)
    }
    
    @ViewBuilder
    private func carouselControls(pageWidth: CGFloat) -> some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 0) {
                carouselControlsContent()
            }
            .padding(.horizontal, 18)
            .frame(width: pageWidth, height: metrics.bannerHeight)
            .contentShape(Rectangle())
            .allowsHitTesting(true)
        } else {
            carouselControlsContent()
                .padding(.horizontal, 18)
                .frame(width: pageWidth, height: metrics.bannerHeight)
                .contentShape(Rectangle())
                .allowsHitTesting(true)
        }
    }

    private func carouselControlsContent() -> some View {
        HStack {
            carouselButton(systemImage: "chevron.left", isEnabled: canMoveBackward) {
                moveSelection(by: -1)
            }

            Spacer()

            carouselButton(systemImage: "chevron.right", isEnabled: canMoveForward) {
                moveSelection(by: 1)
            }
        }
    }

    private func carouselPage(for item: CatalogItem, pageWidth: CGFloat) -> some View {
        NavigationLink(destination: InfoView(item: item)) {
            FeaturedCarouselPage(item: item)
        }
        .buttonStyle(.plain)
        .frame(width: pageWidth, height: metrics.bannerHeight)
        .contentShape(Rectangle())
        .id(item.id)
        #if os(macOS)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        #endif
    }
    
}

private struct FeaturedCarouselPage: View {
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
        return 28
        #else
        return 32
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

struct FeaturedCarousel_Previews: PreviewProvider {
    static var previews: some View {
        FeaturedCarousel(items: featuredItems)
            .background(Color.black)
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
