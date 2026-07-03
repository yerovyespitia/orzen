import Combine
import Foundation

@MainActor
final class SearchCatalogStore: ObservableObject {
    static let shared = SearchCatalogStore()
    static let suggestedTerms = ["Action", "Comedy", "Drama", "Sci-Fi", "Anime", "2025"]

    @Published private(set) var results: [CatalogItem] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var completedQuery = ""

    private var catalog: [CatalogItem] = []
    private var hasPreparedIndex = false
    private var prepareTask: Task<Void, Never>?
    private var searchTask: Task<SearchCatalogResult, Never>?
    private var currentSearchID = UUID()

    private init() {}

    func prepareIndexIfNeeded(forceRefresh: Bool = false) async {
        if forceRefresh {
            hasPreparedIndex = false
            catalog = []
        }

        guard forceRefresh || !hasPreparedIndex else { return }
        guard prepareTask == nil else {
            await prepareTask?.value
            return
        }

        errorMessage = nil

        let task = Task { @MainActor in
            let loadedCatalog = await loadSearchCatalog(forceRefresh: forceRefresh)
            catalog = loadedCatalog.items
            errorMessage = loadedCatalog.didUseFallback
                ? "Could not refresh remote content. Searching available local content instead."
                : nil
            hasPreparedIndex = true
        }

        prepareTask = task
        await task.value
        prepareTask = nil
    }

    func updateSearch(for query: String) async {
        searchTask?.cancel()
        let searchID = UUID()
        currentSearchID = searchID

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            results = []
            isSearching = false
            completedQuery = ""
            return
        }

        isSearching = true
        errorMessage = nil

        let currentCatalog = catalog
        let task = Task(priority: .userInitiated) { () -> SearchCatalogResult in
            async let movieSearch = Self.remoteSearch(type: .movie, query: trimmedQuery)
            async let seriesSearch = Self.remoteSearch(type: .series, query: trimmedQuery)
            let localResults = Self.search(query: trimmedQuery, in: currentCatalog)
            let remoteSearches = await [movieSearch, seriesSearch]
            let remoteResults = remoteSearches.flatMap(\.items)
            let didFailRemote = remoteSearches.contains { $0.didFail }

            return SearchCatalogResult(
                items: Self.uniqueItems(from: remoteResults + localResults),
                didFailRemote: didFailRemote,
                didUseLocalFallback: remoteResults.isEmpty && !localResults.isEmpty
            )
        }

        searchTask = task

        let searchResult = await task.value
        guard currentSearchID == searchID else { return }

        results = searchResult.items
        completedQuery = trimmedQuery

        if searchResult.didFailRemote && searchResult.items.isEmpty {
            errorMessage = "Could not reach Cinemeta search. Check your connection and try again."
        } else if searchResult.didUseLocalFallback {
            errorMessage = nil
        }

        if catalog.isEmpty {
            await prepareIndexIfNeeded()
            guard currentSearchID == searchID else { return }
            if results.isEmpty {
                results = Self.search(query: trimmedQuery, in: catalog)
            }
        }

        if results.isEmpty && searchResult.didFailRemote {
            errorMessage = "Could not reach Cinemeta search. Check your connection and try again."
        } else if results.isEmpty {
            errorMessage = nil
        } else if !results.isEmpty {
            errorMessage = nil
        }

        guard currentSearchID == searchID else {
            results = []
            return
        }

        isSearching = false
    }

    func shouldShowEmptyState(for query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedQuery.count >= 3
            && !isSearching
            && errorMessage == nil
            && completedQuery == trimmedQuery
            && results.isEmpty
    }

    func forceReload() async {
        await prepareIndexIfNeeded(forceRefresh: true)
    }

    private func loadSearchCatalog(forceRefresh: Bool) async -> SearchCatalogLoadResult {
        let requests: [(CinemetaType, CinemetaCatalog, String?)] = [
            (.movie, .top, nil),
            (.movie, .imdbRating, nil),
            (.movie, .top, "Action"),
            (.movie, .top, "Comedy"),
            (.series, .top, nil),
            (.series, .imdbRating, nil),
            (.series, .top, "Drama"),
            (.series, .top, "Sci-Fi")
        ]

        var loadedItems: [CatalogItem] = []
        var loadedRemoteContent = false

        await withTaskGroup(of: [CatalogItem]?.self) { group in
            for request in requests {
                group.addTask {
                    try? await CinemetaClient.fetchCatalog(
                        type: request.0,
                        catalog: request.1,
                        genre: request.2,
                        forceRefresh: forceRefresh
                    )
                }
            }

            for await response in group {
                guard let response, !response.isEmpty else { continue }
                loadedRemoteContent = true
                loadedItems.append(contentsOf: response)
            }
        }

        if loadedRemoteContent {
            return SearchCatalogLoadResult(
                items: Self.uniqueItems(from: loadedItems),
                didUseFallback: false
            )
        }

        return SearchCatalogLoadResult(
            items: Self.uniqueItems(from: movies + series + featuredItems + upcoming),
            didUseFallback: true
        )
    }

    nonisolated private static func search(query: String, in items: [CatalogItem]) -> [CatalogItem] {
        let normalizedQuery = normalized(query)

        return items
            .filter { item in
                let haystack = [
                    item.title,
                    item.description,
                    item.year,
                    item.runtime,
                    item.imdbRating,
                    item.genres.joined(separator: " ")
                ]
                .compactMap { $0 }
                .map(normalized)
                .joined(separator: " ")

                return haystack.contains(normalizedQuery)
            }
            .sorted { lhs, rhs in
                let lhsTitle = normalized(lhs.title)
                let rhsTitle = normalized(rhs.title)

                let lhsStarts = lhsTitle.hasPrefix(normalizedQuery)
                let rhsStarts = rhsTitle.hasPrefix(normalizedQuery)

                if lhsStarts != rhsStarts {
                    return lhsStarts && !rhsStarts
                }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    nonisolated private static func remoteSearch(type: CinemetaType, query: String) async -> SearchRemoteResult {
        do {
            let items = try await CinemetaClient.searchCatalog(type: type, query: query)
            return SearchRemoteResult(items: items, didFail: false)
        } catch {
            return SearchRemoteResult(items: [], didFail: true)
        }
    }

    nonisolated private static func uniqueItems(from items: [CatalogItem]) -> [CatalogItem] {
        var seen = Set<String>()

        return items.filter { item in
            guard !item.title.isEmpty else { return false }
            return seen.insert(item.id).inserted
        }
    }

    nonisolated private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct SearchCatalogLoadResult {
    let items: [CatalogItem]
    let didUseFallback: Bool
}

private struct SearchCatalogResult {
    let items: [CatalogItem]
    let didFailRemote: Bool
    let didUseLocalFallback: Bool
}

private struct SearchRemoteResult {
    let items: [CatalogItem]
    let didFail: Bool
}
