import Foundation

struct CatalogItem: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let imageName: String? // Nombre de la imagen local, si existe
    let description: String
    let posterURL: URL?
    let backgroundURL: URL?
    let year: String?
    let runtime: String?
    let genres: [String]
    let imdbRating: String?
    let cinemetaType: CinemetaType?

    var displayYear: String? {
        year?.trimmingCharacters(in: CharacterSet(charactersIn: "-–— "))
    }

    var homeBannerBackgroundURL: URL? {
        guard let backgroundURL,
              backgroundURL.host == "images.metahub.space",
              var components = URLComponents(url: backgroundURL, resolvingAgainstBaseURL: false) else {
            return backgroundURL
        }

        components.path = components.path.replacingOccurrences(
            of: "/background/medium/",
            with: "/background/large/"
        )

        return components.url ?? backgroundURL
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        imageName: String? = nil,
        description: String,
        posterURL: URL? = nil,
        backgroundURL: URL? = nil,
        year: String? = nil,
        runtime: String? = nil,
        genres: [String] = [],
        imdbRating: String? = nil,
        cinemetaType: CinemetaType? = nil
    ) {
        self.id = id
        self.title = title
        self.imageName = imageName
        self.description = description
        self.posterURL = posterURL
        self.backgroundURL = backgroundURL
        self.year = year
        self.runtime = runtime
        self.genres = genres
        self.imdbRating = imdbRating
        self.cinemetaType = cinemetaType
    }
}

struct CatalogDetail: Codable, Sendable {
    let episodes: [CatalogEpisode]

    static let empty = CatalogDetail(episodes: [])
}

struct CatalogEpisode: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let description: String?
    let thumbnailURL: URL?
    let runtime: String?
    let released: String?
    let season: Int?
    let episode: Int?

    var displayTitle: String {
        title.isEmpty ? "Untitled episode" : title
    }

    var playbackTitle: String {
        guard let seasonEpisodeLabel else { return displayTitle }
        return "\(seasonEpisodeLabel) - \(displayTitle)"
    }

    var metadata: [String] {
        [
            seasonEpisodeLabel,
            runtime,
            released.map(Self.displayDate)
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
    }

    private var seasonEpisodeLabel: String? {
        switch (season, episode) {
        case let (.some(season), .some(episode)):
            "S\(season) E\(episode)"
        case let (.some(season), .none):
            "Season \(season)"
        case let (.none, .some(episode)):
            "Episode \(episode)"
        default:
            nil
        }
    }

    private static func displayDate(_ value: String) -> String {
        if value.count >= 10 {
            return String(value.prefix(10))
        }

        return value
    }
}

enum CinemetaType: String, Codable, Sendable {
    case movie
    case series
}

enum CinemetaCatalog: String, CaseIterable, Identifiable, Codable, Sendable {
    case top
    case year
    case imdbRating

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top:
            "Popular"
        case .year:
            "New"
        case .imdbRating:
            "Featured"
        }
    }
}
