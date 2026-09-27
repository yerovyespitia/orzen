import Foundation

enum CinemetaCatalogFetchSource: Equatable, Sendable {
    case memory
    case disk
    case remote
}

struct CinemetaCatalogFetchResult: Sendable {
    let items: [CatalogItem]
    let source: CinemetaCatalogFetchSource
}

enum CinemetaClient {
    private static let baseURL = URL(string: "https://v3-cinemeta.strem.io")!
    private static let cache = CinemetaCatalogMemoryCache()
    private static let diskCache = CinemetaCatalogDiskCache()
    private static let detailCache = CinemetaDetailMemoryCache()

    static func fetchCatalog(
        type: CinemetaType,
        catalog: CinemetaCatalog,
        genre: String? = nil,
        search: String? = nil,
        skip: Int? = nil,
        forceRefresh: Bool = false
    ) async throws -> [CatalogItem] {
        try await fetchCatalogResult(
            type: type,
            catalog: catalog,
            genre: genre,
            search: search,
            skip: skip,
            forceRefresh: forceRefresh
        ).items
    }

    static func searchCatalog(type: CinemetaType, query: String) async throws -> [CatalogItem] {
        try await fetchCatalog(type: type, catalog: .top, search: query, forceRefresh: true)
    }

    static func fetchItem(type: CinemetaType, id: String) async throws -> CatalogItem {
        let url = baseURL
            .appending(path: "meta")
            .appending(path: type.rawValue)
            .appending(path: id)
            .appendingPathExtension("json")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(CinemetaItemResponse.self, from: data).meta.item(type: type)
    }

    static func fetchCatalogResult(
        type: CinemetaType,
        catalog: CinemetaCatalog,
        genre: String? = nil,
        search: String? = nil,
        skip: Int? = nil,
        forceRefresh: Bool = false
    ) async throws -> CinemetaCatalogFetchResult {
        let cacheKey = CinemetaCatalogCacheKey(
            type: type,
            catalog: catalog,
            genre: genre,
            search: search,
            skip: skip
        )

        if !forceRefresh, let cachedItems = await cache.items(for: cacheKey) {
            return CinemetaCatalogFetchResult(items: cachedItems, source: .memory)
        }

        if !forceRefresh, let cachedItems = await diskCache.items(for: cacheKey) {
            await cache.store(cachedItems, for: cacheKey)
            return CinemetaCatalogFetchResult(items: cachedItems, source: .disk)
        }

        let url = catalogURL(type: type, catalog: catalog, genre: genre, search: search, skip: skip)
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let catalogResponse = try JSONDecoder().decode(CinemetaCatalogResponse.self, from: data)
        let loadedItems = catalogResponse.metas.map { $0.item(type: type) }
        await cache.store(loadedItems, for: cacheKey)
        await diskCache.store(loadedItems, for: cacheKey)
        return CinemetaCatalogFetchResult(items: loadedItems, source: .remote)
    }

    static func fetchDetail(for item: CatalogItem, forceRefresh: Bool = false) async throws -> CatalogDetail {
        guard let type = item.cinemetaType else {
            return .empty
        }

        let cacheKey = CinemetaDetailCacheKey(type: type, id: item.id)

        if !forceRefresh, let cachedDetail = await detailCache.detail(for: cacheKey) {
            return cachedDetail
        }

        let url = baseURL
            .appending(path: "meta")
            .appending(path: type.rawValue)
            .appending(path: item.id)
            .appendingPathExtension("json")

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let detailResponse = try JSONDecoder().decode(CinemetaDetailResponse.self, from: data)
        let detail = detailResponse.detail
        await detailCache.store(detail, for: cacheKey)
        return detail
    }

    static func cachedDetail(for item: CatalogItem) async -> CatalogDetail? {
        guard let type = item.cinemetaType else {
            return .empty
        }

        return await detailCache.detail(for: CinemetaDetailCacheKey(type: type, id: item.id))
    }

    private static func catalogURL(
        type: CinemetaType,
        catalog: CinemetaCatalog,
        genre: String?,
        search: String?,
        skip: Int?
    ) -> URL {
        let extras = [
            genre.map { "genre=\(encodedExtraValue($0))" },
            search.map { "search=\(encodedExtraValue($0))" },
            skip.map { "skip=\($0)" }
        ].compactMap { $0 }

        var pathComponents = [
            baseURL.absoluteString,
            "catalog",
            type.rawValue,
            catalog.rawValue
        ]

        if !extras.isEmpty {
            pathComponents.append(extras.joined(separator: "&"))
        }

        let urlString = pathComponents.joined(separator: "/") + ".json"
        return URL(string: urlString)!
    }

    private static func encodedExtraValue(_ value: String) -> String {
        var allowedCharacters = CharacterSet.urlPathAllowed
        allowedCharacters.remove(charactersIn: "/&=?")
        return value.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? value
    }
}

private struct CinemetaCatalogCacheKey: Hashable, Codable, Sendable {
    let type: CinemetaType
    let catalog: CinemetaCatalog
    let genre: String?
    let search: String?
    let skip: Int?
}

private struct CinemetaDetailCacheKey: Hashable, Sendable {
    let type: CinemetaType
    let id: String
}

private actor CinemetaCatalogMemoryCache {
    private var catalogs: [CinemetaCatalogCacheKey: [CatalogItem]] = [:]

    func items(for key: CinemetaCatalogCacheKey) -> [CatalogItem]? {
        catalogs[key]
    }

    func store(_ items: [CatalogItem], for key: CinemetaCatalogCacheKey) {
        catalogs[key] = items
    }
}

private actor CinemetaCatalogDiskCache {
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let cacheDirectory: URL

    init() {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        cacheDirectory = baseDirectory
            .appending(path: "Orzen", directoryHint: .isDirectory)
            .appending(path: "CinemetaCatalogCache", directoryHint: .isDirectory)
    }

    func items(for key: CinemetaCatalogCacheKey) -> [CatalogItem]? {
        let fileURL = fileURL(for: key)

        guard let data = try? Data(contentsOf: fileURL),
              let entry = try? decoder.decode(CinemetaCatalogDiskCacheEntry.self, from: data) else {
            return nil
        }

        return entry.items
    }

    func store(_ items: [CatalogItem], for key: CinemetaCatalogCacheKey) {
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let entry = CinemetaCatalogDiskCacheEntry(createdAt: Date(), items: items)
            let data = try encoder.encode(entry)
            try data.write(to: fileURL(for: key), options: .atomic)
        } catch {
            assertionFailure("Could not persist Cinemeta catalog cache: \(error)")
        }
    }

    private func fileURL(for key: CinemetaCatalogCacheKey) -> URL {
        cacheDirectory.appending(path: "\(filename(for: key)).json")
    }

    private func filename(for key: CinemetaCatalogCacheKey) -> String {
        [
            key.type.rawValue,
            key.catalog.rawValue,
            key.genre ?? "all",
            key.search ?? "browse",
            key.skip.map(String.init) ?? "0"
        ]
        .map(sanitizedFilenameComponent)
        .joined(separator: "_")
    }

    private func sanitizedFilenameComponent(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

private struct CinemetaCatalogDiskCacheEntry: Codable, Sendable {
    let createdAt: Date
    let items: [CatalogItem]
}

private actor CinemetaDetailMemoryCache {
    private var details: [CinemetaDetailCacheKey: CatalogDetail] = [:]

    func detail(for key: CinemetaDetailCacheKey) -> CatalogDetail? {
        details[key]
    }

    func store(_ detail: CatalogDetail, for key: CinemetaDetailCacheKey) {
        details[key] = detail
    }
}

private struct CinemetaCatalogResponse: Decodable {
    let metas: [CinemetaMeta]
}

private struct CinemetaItemResponse: Decodable {
    let meta: CinemetaMeta
}

private struct CinemetaDetailResponse: Decodable {
    let meta: CinemetaDetailedMeta

    var detail: CatalogDetail {
        CatalogDetail(episodes: meta.videos?.enumerated().map { index, video in
            video.catalogEpisode(fallbackIndex: index)
        } ?? [])
    }
}

private struct CinemetaDetailedMeta: Decodable {
    let videos: [CinemetaVideo]?
}

private struct CinemetaMeta: Decodable {
    let id: String
    let name: String
    let description: String?
    let poster: URL?
    let background: URL?
    let year: String?
    let releaseInfo: String?
    let runtime: String?
    let genres: [String]?
    let genre: [String]?
    let imdbRating: String?

    func item(type: CinemetaType) -> CatalogItem {
        CatalogItem(
            id: id,
            title: name,
            description: description ?? "No description available.",
            posterURL: poster,
            backgroundURL: background,
            year: year ?? releaseInfo,
            runtime: runtime,
            genres: genres ?? genre ?? [],
            imdbRating: imdbRating,
            cinemetaType: type
        )
    }
}

private struct CinemetaVideo: Decodable {
    let id: String?
    let title: String?
    let name: String?
    let overview: String?
    let description: String?
    let thumbnail: String?
    let released: String?
    let runtime: String?
    let season: Int?
    let episode: Int?
    let number: Int?

    func catalogEpisode(fallbackIndex: Int) -> CatalogEpisode {
        let resolvedEpisode = episode ?? number
        let resolvedTitle = title ?? name ?? resolvedEpisode.map { "Episode \($0)" } ?? "Untitled episode"
        let resolvedID = id ?? [season.map(String.init), resolvedEpisode.map(String.init)]
            .compactMap { $0 }
            .joined(separator: "-")

        return CatalogEpisode(
            id: resolvedID.isEmpty ? "episode-\(fallbackIndex)" : resolvedID,
            title: resolvedTitle,
            description: overview ?? description,
            thumbnailURL: thumbnail.flatMap(URL.init(string:)),
            runtime: runtime,
            released: released,
            season: season,
            episode: resolvedEpisode
        )
    }
}
