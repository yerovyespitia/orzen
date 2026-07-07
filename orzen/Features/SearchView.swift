import SwiftUI

struct SearchView: View {
    var scrollToTopRequest = 0

    @State private var searchText = ""
    @State private var detailItemFromContextMenu: CatalogItem?
    @State private var isShowingContextMenuDetail = false
    @ObservedObject private var searchStore = SearchCatalogStore.shared
    private let scrollTopID = "search-scroll-top"

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 20) {
                    searchBar
                    content
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 20)
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
        .task {
            await searchStore.prepareIndexIfNeeded()
        }
        .task(id: searchText) {
            let currentQuery = searchText

            do {
                try await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                await searchStore.updateSearch(for: currentQuery)
            } catch {
                return
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("Search movies, series, genres...", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundColor(.white)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .clipShape(Capsule())
        .padding(.horizontal)
    }

    @ViewBuilder
    private var content: some View {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if searchStore.isSearching {
            ProgressView("Searching...")
                .tint(.white)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else if trimmedSearchText.isEmpty {
            suggestedSearches
        } else if let errorMessage = searchStore.errorMessage {
            ContentUnavailableView {
                Label("Search unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Retry") {
                    Task {
                        await searchStore.forceReload()
                        await searchStore.updateSearch(for: searchText)
                    }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchStore.shouldShowEmptyState(for: trimmedSearchText) {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundColor(.gray)

                Text("No results found")
                    .foregroundColor(.gray)

                Text("Try another title, genre, or year.")
                    .foregroundColor(.gray.opacity(0.75))
            }
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
                        ForEach(searchStore.results) { item in
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
                .frame(maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .bottom)
                .orzenTopScrollEdgeEffect()
                .onChange(of: scrollToTopRequest) { _, _ in
                    scrollToTop(with: scrollProxy)
                }
            }
        }
    }

    private var suggestedSearches: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Popular Searches")
                .font(.title2)
                .foregroundColor(.white)
                .padding(.horizontal)
                .fontWeight(.medium)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(SearchCatalogStore.suggestedTerms, id: \.self) { term in
                        Button {
                            searchText = term
                        } label: {
                            Text(term)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(20)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

#Preview {
    SearchView()
}
