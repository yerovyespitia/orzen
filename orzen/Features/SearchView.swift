import SwiftUI

struct SearchView: View {
    private var scrollToTopRequest: Int
    private var popToRootRequest: Int
    private var externalSearchText: Binding<String>?
    private var showsSearchBar: Bool
    private var systemSearchActivationRequest: Int

    @State private var localSearchText = ""
    @State private var detailItemFromContextMenu: CatalogItem?
    @State private var isShowingContextMenuDetail = false
    @State private var isSystemSearchPresented = false
    @ObservedObject private var searchStore = SearchCatalogStore.shared
    private let scrollTopID = "search-scroll-top"

    init(
        scrollToTopRequest: Int = 0,
        popToRootRequest: Int = 0,
        searchText: Binding<String>? = nil,
        showsSearchBar: Bool = true,
        systemSearchActivationRequest: Int = 0
    ) {
        self.scrollToTopRequest = scrollToTopRequest
        self.popToRootRequest = popToRootRequest
        self.externalSearchText = searchText
        self.showsSearchBar = showsSearchBar
        self.systemSearchActivationRequest = systemSearchActivationRequest
    }

    var body: some View {
        searchContainer
            .task {
                await searchStore.prepareIndexIfNeeded()
            }
            .task(id: searchTextValue) {
                let currentQuery = searchTextValue

                do {
                    try await Task.sleep(for: .milliseconds(450))
                    guard !Task.isCancelled else { return }
                    await searchStore.updateSearch(for: currentQuery)
                } catch {
                    return
                }
            }
    }

    @ViewBuilder
    private var searchContainer: some View {
        #if os(iOS)
        if showsSearchBar {
            navigationContent
        } else {
            navigationContent
                .searchable(text: searchTextBinding, isPresented: $isSystemSearchPresented)
                .onAppear {
                    presentSystemSearch()
                }
                .onChange(of: systemSearchActivationRequest) { _, _ in
                    presentSystemSearch()
                }
        }
        #else
        navigationContent
        #endif
    }

    private var navigationContent: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 20) {
                    if showsSearchBar {
                        searchBar
                    }

                    content
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, showsSearchBar ? 20 : 0)
            }
            .navigationDestination(isPresented: $isShowingContextMenuDetail) {
                if let detailItemFromContextMenu {
                    InfoView(item: detailItemFromContextMenu)
                }
            }
            #if os(iOS)
            .popNavigationToRoot(on: popToRootRequest)
            #endif
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .interactivePopGestureEnabled()
        #endif
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("Search movies, series, genres...", text: searchTextBinding)
                .textFieldStyle(.plain)
                .foregroundColor(.white)

            if !searchTextValue.isEmpty {
                Button {
                    searchTextBinding.wrappedValue = ""
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
        let trimmedSearchText = searchTextValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if searchStore.isSearching {
            ProgressView("Searching...")
                .tint(.white)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else if trimmedSearchText.isEmpty {
            emptySearchContent
        } else if let errorMessage = searchStore.errorMessage {
            ContentUnavailableView {
                Label("Search unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Retry") {
                    Task {
                        await searchStore.forceReload()
                        await searchStore.updateSearch(for: searchTextValue)
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
                    .padding(.bottom, 22)
                }
                .frame(maxHeight: .infinity)
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
                            searchTextBinding.wrappedValue = term
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

    @ViewBuilder
    private var emptySearchContent: some View {
        if showsSearchBar {
            suggestedSearches
        } else {
            VStack(spacing: 0) {
                suggestedSearches
                    .padding(.top, 18)

                Spacer(minLength: 0)

                recentSearchesEmptyState

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var recentSearchesEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 56, weight: .regular))
                .foregroundColor(.gray)

            Text("No Recent Searches")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text("Your recent searches will appear here.")
                .foregroundColor(.gray.opacity(0.75))
        }
        .padding(.horizontal, OrzenLayout.current.contentLeadingInset)
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

    private var searchTextBinding: Binding<String> {
        externalSearchText ?? $localSearchText
    }

    private var searchTextValue: String {
        searchTextBinding.wrappedValue
    }

    #if os(iOS)
    private func presentSystemSearch() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            isSystemSearchPresented = true
        }
    }
    #endif
}

#Preview {
    SearchView()
}
