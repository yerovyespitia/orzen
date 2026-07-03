import SwiftUI

struct CinemetaCatalogView: View {
    let title: String
    let type: CinemetaType
    let filters: [String]
    let fallbackItems: [CatalogItem]
    var scrollToTopRequest: Int

    @ObservedObject private var catalogStore: CinemetaCatalogStore
    @State private var detailItemFromContextMenu: CatalogItem?
    @State private var isShowingContextMenuDetail = false
    private let scrollTopID = "cinemeta-catalog-scroll-top"

    init(
        title: String,
        type: CinemetaType,
        filters: [String],
        fallbackItems: [CatalogItem],
        scrollToTopRequest: Int = 0
    ) {
        self.title = title
        self.type = type
        self.filters = filters
        self.fallbackItems = fallbackItems
        self.scrollToTopRequest = scrollToTopRequest
        _catalogStore = ObservedObject(wrappedValue: CinemetaCatalogStore.shared(
            title: title,
            type: type,
            filters: filters,
            fallbackItems: fallbackItems
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    header
                    filterBar
                    content
                }
            }
            .navigationDestination(isPresented: $isShowingContextMenuDetail) {
                if let detailItemFromContextMenu {
                    InfoView(item: detailItemFromContextMenu)
                }
            }
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .interactivePopGestureEnabled()
        #endif
        .task(id: catalogStore.selectedFilter) {
            await catalogStore.loadCatalog()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(headerTitleFont)
                .fontWeight(.bold)
                .foregroundColor(.white)

            if catalogStore.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }

            Spacer()

            Button {
                Task { await catalogStore.loadCatalog(forceRefresh: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundColor(.white.opacity(0.82))
            .help("Reload catalog")
        }
        .padding(.horizontal)
    }

    private var headerTitleFont: Font {
        #if os(iOS)
        return .title2
        #else
        return .title
        #endif
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(filters, id: \.self) { filter in
                    FilterButton(
                        title: filter,
                        isSelected: catalogStore.selectedFilter == filter,
                        action: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                catalogStore.selectedFilter = filter
                            }
                        }
                    )
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = catalogStore.errorMessage, catalogStore.items.isEmpty {
            ContentUnavailableView {
                Label("Catalog unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Retry") {
                    Task { await catalogStore.loadCatalog(forceRefresh: true) }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    Color.clear
                        .frame(height: 0)
                        .id(scrollTopID)

                    LazyVGrid(
                        columns: OrzenLayout.posterGridColumns,
                        alignment: .leading,
                        spacing: OrzenLayout.current.gridVerticalSpacing
                    ) {
                        ForEach(displayItems) { item in
                            NavigationLink(destination: InfoView(item: item)) {
                                CatalogPosterCard(
                                    item: item,
                                    onViewDetails: {
                                        showContextMenuDetail(for: item)
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, OrzenLayout.current.contentLeadingInset)
                    .padding(.bottom, 24)
                }
                .onChange(of: scrollToTopRequest) { _, _ in
                    scrollToTop(with: scrollProxy)
                }
            }
        }
    }

    private var displayItems: [CatalogItem] {
        catalogStore.items.isEmpty ? fallbackItems : catalogStore.items
    }

    private func showContextMenuDetail(for item: CatalogItem) {
        detailItemFromContextMenu = item
        isShowingContextMenuDetail = true
    }

    private func scrollToTop(with scrollProxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.18)) {
            scrollProxy.scrollTo(scrollTopID, anchor: .top)
        }
    }
}
