import Foundation
import os
import Security

struct TorznabConfiguration: Sendable {
    let endpoint: URL
    let apiKey: String
}

enum TorznabSearchError: LocalizedError {
    case notConfigured
    case invalidEndpoint
    case badResponse
    case invalidFeed
    case provider(String)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Add a Torznab search endpoint in Settings."
        case .invalidEndpoint: "Enter a valid HTTP or HTTPS Torznab API URL."
        case .badResponse: "The search provider did not return a successful response."
        case .invalidFeed: "The search provider returned an unreadable feed."
        case .provider(let message): message
        case .keychain: "The API key could not be saved securely."
        }
    }
}

@MainActor
final class TorznabSettingsStore: ObservableObject {
    static let shared = TorznabSettingsStore()

    @Published var endpointText: String
    @Published var apiKey: String
    @Published private(set) var saveMessage: String?

    private static let endpointKey = "localMedia.torznabEndpoint"
    private static var keychainService: String {
        #if DEBUG
        if let suite = LocalMediaServiceRuntime.testValue("ORZEN_SERVICE_TEST_DEFAULTS") {
            return suite + ".torznab" + (LocalMediaServiceRuntime.isService ? ".service" : "")
        }
        #endif
        return "com.yerovyespitia.orzen.torznab" + (LocalMediaServiceRuntime.isService ? ".service" : "")
    }
    private static let keychainAccount = "apiKey"

    private init() {
        endpointText = LocalMediaServiceRuntime.defaults.string(forKey: Self.endpointKey) ?? ""
        apiKey = Self.loadAPIKey() ?? ""
    }

    var configuration: TorznabConfiguration? {
        guard let savedEndpoint = LocalMediaServiceRuntime.defaults.string(forKey: Self.endpointKey),
              let endpoint = Self.validEndpoint(savedEndpoint) else { return nil }
        return TorznabConfiguration(endpoint: endpoint, apiKey: Self.loadAPIKey() ?? "")
    }

    func save() {
        let trimmedEndpoint = endpointText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEndpoint.isEmpty || Self.validEndpoint(trimmedEndpoint) != nil,
              var components = URLComponents(string: trimmedEndpoint.isEmpty ? "https://example.invalid" : trimmedEndpoint) else {
            saveMessage = TorznabSearchError.invalidEndpoint.localizedDescription
            return
        }

        let embeddedKey = components.queryItems?
            .first(where: { $0.name.lowercased() == "apikey" })?.value
        components.queryItems = components.queryItems?.filter { $0.name.lowercased() != "apikey" }
        let savedEndpoint = trimmedEndpoint.isEmpty ? "" : (components.url?.absoluteString ?? trimmedEndpoint)
        let savedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedKey = savedKey.isEmpty ? (embeddedKey ?? "") : savedKey

        do {
            try Self.saveAPIKey(resolvedKey)
            endpointText = savedEndpoint
            apiKey = resolvedKey
            LocalMediaServiceRuntime.defaults.set(savedEndpoint, forKey: Self.endpointKey)
            saveMessage = "Search provider saved."
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    func reportServiceStatus(_ message: String) { saveMessage = message }

    private static func validEndpoint(_ value: String) -> URL? {
        guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil,
              let url = components.url else { return nil }
        return url
    }

    private static func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func saveAPIKey(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]

        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw TorznabSearchError.keychain(status)
            }
            return
        }

        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw TorznabSearchError.keychain(addStatus)
            }
        } else if status != errSecSuccess {
            throw TorznabSearchError.keychain(status)
        }
    }
}

struct TorrentSearchResult: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let infoHash: String?
    let downloadURL: URL?
    let size: Int64?
    let seeders: Int?
    let peers: Int?

    var inferredTracks: LocalMediaTrackLanguages {
        LocalMediaTrackLanguages.infer(from: title)
    }

    var languageLabel: String? {
        if inferredTracks.audio.contains(where: { $0.hasPrefix("ES") }) {
            return "Spanish"
        }
        if inferredTracks.audio.contains("EN") {
            return "English"
        }
        return nil
    }

    var qualityLabel: String? {
        title.range(of: #"\b(2160p|1080p|720p|480p|4K)\b"#, options: [.regularExpression, .caseInsensitive])
            .map { String(title[$0]) }
    }
}

struct LocalMediaTrackLanguages: Sendable {
    let audio: [String]
    let subtitles: [String]

    static func infer(from title: String) -> LocalMediaTrackLanguages {
        let words = title.folding(options: [.diacriticInsensitive], locale: .current)
            .uppercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        var audio: [String] = []
        var subtitles: [String] = []
        var inSubtitles = false
        for word in words {
            if ["SUB", "SUBS", "SUBTITLE", "SUBTITLES", "SUBBED"].contains(word) {
                inSubtitles = true
                continue
            }
            if ["AUDIO", "DUB", "DUBBED"].contains(word) {
                inSubtitles = false
                continue
            }
            if word == "VOSTFR" {
                if !subtitles.contains("FR") { subtitles.append("FR") }
                continue
            }
            // LAT in release names means Latin American Spanish; as a media language code it means Latin.
            guard let code = word == "LAT" ? "ES-LAT" : normalizedCode(word, fromFilename: true) else { continue }
            if inSubtitles {
                if !subtitles.contains(code) { subtitles.append(code) }
            } else if !audio.contains(code) {
                audio.append(code)
            }
        }
        return LocalMediaTrackLanguages(audio: audio, subtitles: subtitles)
    }

    static func normalizedCode(_ value: String, fromFilename: Bool = false) -> String? {
        let code = value.folding(options: [.diacriticInsensitive], locale: .current).uppercased()
        switch code {
        case "ENG", "ENGLISH", "INGLES": return "EN"
        case "ITA", "ITALIAN", "ITALIANO": return "IT"
        case "SPA", "SPANISH", "ESP", "ESPANOL": return "ES"
        case "CASTELLANO": return "ES-ES"
        case "LATINO", "LATAM": return "ES-LAT"
        case "FRA", "FRE", "FRENCH", "FRANCES": return "FR"
        case "DEU", "GER", "GERMAN", "ALEMAN": return "DE"
        case "POR", "PORTUGUESE", "PORTUGUES": return "PT"
        case "JPN", "JAPANESE", "JAPONES": return "JA"
        case "KOR", "KOREAN", "COREANO": return "KO"
        case "HIN", "HINDI": return "HI"
        default:
            if !fromFilename {
                switch code {
                case "EN", "IT", "ES", "FR", "DE", "PT", "JA", "KO", "HI": return code
                default: break
                }
            }
            return nil
        }
    }
}

enum TorznabSearchClient {
    static func search(
        configuration: TorznabConfiguration,
        item: CatalogItem,
        episode: CatalogEpisode?,
        searchTitle: String,
        includeSpanish: Bool
    ) async throws -> [TorrentSearchResult] {
        let title = searchTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return [] }

        let queries = TorrentSearchStrategy.queries(title: title, item: item, episode: episode)
        guard let baseQuery = queries.first else { return [] }
        var queriesToFetch = queries
        if includeSpanish {
            queriesToFetch += ["\(baseQuery) castellano", "\(baseQuery) latino"]
        }
        let category: String
        if item.cinemetaType == .series {
            category = TorrentSearchStrategy.isAnime(item) ? "5070" : "5000"
        } else {
            category = "2000"
        }

        var found: [TorrentSearchResult] = []
        var firstError: Error?
        await withTaskGroup(of: Result<[TorrentSearchResult], Error>.self) { group in
            for query in queriesToFetch {
                group.addTask {
                    do { return .success(try await fetch(configuration: configuration, query: query, category: category)) }
                    catch { return .failure(error) }
                }
            }
            for await result in group {
                switch result {
                case .success(let results): found.append(contentsOf: results)
                case .failure(let error): firstError = firstError ?? error
                }
            }
        }
        if found.isEmpty, let firstError { throw firstError }

        var seen = Set<String>()
        return found
            .filter { result in
                let identity = result.infoHash?.lowercased() ?? result.id
                return seen.insert(identity).inserted
            }
            .sorted { ($0.seeders ?? -1) > ($1.seeders ?? -1) }
    }

    private static func fetch(configuration: TorznabConfiguration, query: String, category: String) async throws -> [TorrentSearchResult] {
        guard var components = URLComponents(url: configuration.endpoint, resolvingAgainstBaseURL: false) else {
            throw TorznabSearchError.invalidEndpoint
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { ["t", "q", "apikey", "cat"].contains($0.name.lowercased()) }
        queryItems += [URLQueryItem(name: "t", value: "search"), URLQueryItem(name: "q", value: query)]
        queryItems.append(URLQueryItem(name: "cat", value: category))
        if !configuration.apiKey.isEmpty {
            queryItems.append(URLQueryItem(name: "apikey", value: configuration.apiKey))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw TorznabSearchError.invalidEndpoint }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else { throw TorznabSearchError.badResponse }

        let parser = TorznabFeedParser(data: data)
        guard parser.parse() else { throw TorznabSearchError.invalidFeed }
        if let providerError = parser.providerError { throw TorznabSearchError.provider(providerError) }
        return parser.results
    }
}

private enum TorrentSearchStrategy {
    static func isAnime(_ item: CatalogItem) -> Bool {
        item.genres.contains {
            let genre = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return genre.caseInsensitiveCompare("anime") == .orderedSame
                || genre.caseInsensitiveCompare("animation") == .orderedSame
        }
    }

    static func queries(title: String, item: CatalogItem, episode: CatalogEpisode?) -> [String] {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return [] }

        var suffixes: [String] = []
        if let episode, let number = episode.episode {
            if let season = episode.season {
                suffixes.append(String(format: "S%02dE%02d", season, number))
            }
            if isAnime(item) {
                suffixes.append(String(format: "%02d", number))
                if number < 10 { suffixes.append(String(number)) }
            }
        } else if item.cinemetaType == .movie, let year = item.displayYear?.firstYear {
            suffixes.append(year)
        }

        let queries = suffixes.isEmpty ? [cleanTitle] : suffixes.map { "\(cleanTitle) \($0)" }
        var seen = Set<String>()
        return queries.filter { seen.insert($0.lowercased()).inserted }
    }
}

private extension String {
    var firstYear: String? {
        range(of: #"\b(?:19|20)\d{2}\b"#, options: .regularExpression).map { String(self[$0]) }
    }
}

private final class TorznabFeedParser: NSObject, XMLParserDelegate {
    private struct Item {
        var title = ""
        var guid = ""
        var link = ""
        var enclosureURL: String?
        var size: Int64?
        var seeders: Int?
        var peers: Int?
        var infoHash: String?
        var magnetURL: String?
    }

    private let parser: XMLParser
    private var item: Item?
    private var currentText = ""
    private var sawRSSRoot = false
    private(set) var results: [TorrentSearchResult] = []
    private(set) var providerError: String?

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
    }

    func parse() -> Bool { parser.parse() && (sawRSSRoot || providerError != nil) }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if elementName == "rss" { sawRSSRoot = true }
        if elementName == "error" { providerError = attributeDict["description"] ?? "The search provider reported an error." }
        if elementName == "item" {
            item = Item()
        }
        guard item != nil else { return }
        currentText = ""

        if elementName == "enclosure" {
            item?.enclosureURL = attributeDict["url"]
            item?.size = attributeDict["length"].flatMap(Int64.init)
        } else if ["torznab:attr", "newznab:attr", "attr"].contains(elementName) {
            let value = attributeDict["value"]
            switch attributeDict["name"]?.lowercased() {
            case "seeders": item?.seeders = value.flatMap(Int.init)
            case "peers": item?.peers = value.flatMap(Int.init)
            case "infohash": item?.infoHash = value
            case "magneturl": item?.magnetURL = value
            case "size": item?.size = value.flatMap(Int64.init)
            default: break
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        currentText += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard var current = item else { return }
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "title": current.title = value
        case "guid": current.guid = value
        case "link": current.link = value
        case "size": current.size = Int64(value) ?? current.size
        case "item":
            let link = current.magnetURL ?? current.enclosureURL ?? current.link
            let hash = current.infoHash ?? Self.hash(from: link)
            let id = hash ?? (!current.guid.isEmpty ? current.guid : link)
            if !current.title.isEmpty, !id.isEmpty {
                results.append(TorrentSearchResult(
                    id: id,
                    title: current.title,
                    infoHash: hash,
                    downloadURL: URL(string: link),
                    size: current.size,
                    seeders: current.seeders,
                    peers: current.peers
                ))
            }
            item = nil
            currentText = ""
            return
        default: break
        }
        item = current
        currentText = ""
    }

    private static func hash(from link: String) -> String? {
        guard let components = URLComponents(string: link), components.scheme == "magnet",
              let xt = components.queryItems?.first(where: { $0.name == "xt" })?.value,
              xt.lowercased().hasPrefix("urn:btih:") else { return nil }
        return String(xt.dropFirst("urn:btih:".count))
    }
}

@MainActor
enum LocalTorrentSearchClient {
    private struct SearchKey: Hashable {
        let contentID: String
        let includeSpanish: Bool
    }

    private static var cachedResults: [SearchKey: [TorrentSearchResult]] = [:]

    static func search(
        item: CatalogItem,
        episode: CatalogEpisode?,
        includeSpanish: Bool,
        forceRefresh: Bool = false
    ) async throws -> [TorrentSearchResult] {
        let key = SearchKey(contentID: episode?.id ?? item.id, includeSpanish: includeSpanish)
        if !forceRefresh, let cached = cachedResults[key] { return cached }

        let queries = TorrentSearchStrategy.queries(title: item.title, item: item, episode: episode)
        guard let query = queries.first else { return [] }

        do {
            var found: [TorrentSearchResult] = []
            for (index, searchQuery) in queries.enumerated() {
                guard !Task.isCancelled else { break }
                let extra = index == 0
                    ? try await MagnetzSearchClient.fetch(query: searchQuery)
                    : (try? await MagnetzSearchClient.fetch(query: searchQuery)) ?? []
                found.append(contentsOf: extra)
                if !cleaned(found, item: item, episode: episode, includeSpanish: includeSpanish).isEmpty {
                    break
                }
            }

            if includeSpanish,
               !cleaned(found, item: item, episode: episode, includeSpanish: true)
                .contains(where: { $0.languageLabel == "Spanish" }) {
                for language in ["latino", "castellano", "español"] {
                    guard !Task.isCancelled else { break }
                    if let extra = try? await MagnetzSearchClient.fetch(query: "\(query) \(language)") {
                        found.append(contentsOf: extra)
                        if cleaned(found, item: item, episode: episode, includeSpanish: true)
                            .contains(where: { $0.languageLabel == "Spanish" }) {
                            break
                        }
                    }
                }
            }

            if let configuration = TorznabSettingsStore.shared.configuration,
               let extra = try? await TorznabSearchClient.search(configuration: configuration,
                   item: item, episode: episode, searchTitle: item.title, includeSpanish: includeSpanish) {
                found.append(contentsOf: extra)
            }
            guard !Task.isCancelled else { return cachedResults[key] ?? [] }
            let filtered = cleaned(found, item: item, episode: episode, includeSpanish: includeSpanish)
            if filtered.isEmpty {
                cachedResults.removeValue(forKey: key)
            } else {
                cachedResults[key] = filtered
            }
            return filtered
        } catch {
            if !forceRefresh, let cached = cachedResults[key] { return cached }
            throw error
        }
    }

    private static func cleaned(
        _ results: [TorrentSearchResult],
        item: CatalogItem,
        episode: CatalogEpisode?,
        includeSpanish: Bool
    ) -> [TorrentSearchResult] {
        var seen = Set<String>()
        return results
            .filter { isRelevant($0, item: item, episode: episode) }
            .filter { includeSpanish || $0.languageLabel != "Spanish" }
            .filter { seen.insert($0.infoHash?.lowercased() ?? $0.id).inserted }
            .sorted { ($0.seeders ?? -1) > ($1.seeders ?? -1) }
    }

    private static func isRelevant(_ result: TorrentSearchResult, item: CatalogItem, episode: CatalogEpisode?) -> Bool {
        let title = result.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let keywords = item.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 2 && !["the", "and", "los", "las"].contains($0) }
        let titleMatches = !keywords.isEmpty && keywords.allSatisfy({ title.contains($0) })
        guard titleMatches || (TorrentSearchStrategy.isAnime(item) && episode?.episode != nil) else { return false }
        if let episode, let season = episode.season, let number = episode.episode {
            let marker = String(format: "s%02de%02d", season, number)
            let animeEpisodePattern = String(format: #"(?<![A-Za-z0-9])0?%d(?![A-Za-z0-9])"#, number)
            let hasAnimeEpisodeNumber = TorrentSearchStrategy.isAnime(item)
                && title.range(of: animeEpisodePattern, options: .regularExpression) != nil
            guard title.contains(marker) || hasAnimeEpisodeNumber else { return false }
        } else if let episode, let number = episode.episode, TorrentSearchStrategy.isAnime(item) {
            let animeEpisodePattern = String(format: #"(?<![A-Za-z0-9])0?%d(?![A-Za-z0-9])"#, number)
            guard title.range(of: animeEpisodePattern, options: .regularExpression) != nil else { return false }
        }
        return true
    }
}

private enum MagnetzSearchClient {
    private static let logger = Logger(subsystem: "com.yerovyespitia.orzen", category: "MagnetzSearch")

    private struct Response: Decodable { let data: [Entry] }
    private struct Entry: Decodable {
        let name: String
        let infoHash: String
        let magnetLink: String
        let size: Int64?
        let seeders: Int?
        let leechers: Int?

        enum CodingKeys: String, CodingKey {
            case name, size, seeders, leechers
            case infoHash = "info_hash"
            case magnetLink = "magnet_link"
        }
    }

    static func fetch(query: String) async throws -> [TorrentSearchResult] {
        var components = URLComponents(string: "https://magnetz.eu/api/magnets/search")!
        components.queryItems = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "page", value: "1")]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20

        for attempt in 0..<2 {
            let startedAt = Date()
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse else {
                    throw MagnetzSearchError.invalidResponse
                }
                let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
                let remaining = response.value(forHTTPHeaderField: "x-ratelimit-remaining") ?? "unknown"

                if (500..<600).contains(response.statusCode), attempt == 0 {
                    logger.error("Magnetz returned HTTP \(response.statusCode, privacy: .public); retrying once after \(elapsedMilliseconds, privacy: .public)ms")
                    try await Task.sleep(nanoseconds: 750_000_000)
                    continue
                }
                if response.statusCode == 429, attempt == 0,
                   let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init),
                   retryAfter > 0, retryAfter <= 10 {
                    logger.error("Magnetz rate limited the request; retrying after \(retryAfter, privacy: .public)s")
                    try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                    continue
                }
                guard (200..<300).contains(response.statusCode) else {
                    logger.error("Magnetz returned HTTP \(response.statusCode, privacy: .public), remaining=\(remaining, privacy: .public), elapsed=\(elapsedMilliseconds, privacy: .public)ms")
                    throw MagnetzSearchError.httpStatus(response.statusCode)
                }

                logger.notice("Magnetz search succeeded, remaining=\(remaining, privacy: .public), elapsed=\(elapsedMilliseconds, privacy: .public)ms")
                return try JSONDecoder().decode(Response.self, from: data).data.compactMap { entry in
                    guard let magnet = URL(string: entry.magnetLink) else { return nil }
                    return TorrentSearchResult(id: entry.infoHash.lowercased(), title: entry.name,
                        infoHash: entry.infoHash, downloadURL: magnet, size: entry.size,
                        seeders: entry.seeders, peers: entry.leechers)
                }
            } catch let error as MagnetzSearchError {
                throw error
            } catch let error as URLError where error.code != .cancelled && attempt == 0 {
                logger.error("Magnetz transport error \(error.code.rawValue, privacy: .public); retrying once")
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        throw MagnetzSearchError.unavailable
    }
}

private enum MagnetzSearchError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse, .unavailable:
            "Built-in torrent search is temporarily unavailable. Try again in a moment."
        case .httpStatus(429):
            "Built-in torrent search reached its request limit. Wait a moment and try again."
        case .httpStatus:
            "Built-in torrent search is temporarily unavailable. Try again in a moment."
        }
    }
}
