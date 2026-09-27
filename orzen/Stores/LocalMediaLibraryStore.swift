import Foundation

struct LocalMediaVersion: Identifiable, Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case queued
        case downloading
        case paused
        case completed
        case failed
    }

    let id: UUID
    let catalogID: String
    let contentType: CinemetaType
    let episodeID: String?
    let infoHash: String
    let torrentTitle: String
    var catalogItem: CatalogItem?
    let language: String?
    let quality: String?
    let folderRelativePath: String
    var videoRelativePath: String?
    var status: Status
    var magnetURI: String?
    var torrentFileRelativePath: String?
    var progress: Double?
    var downloadedBytes: Int64?
    var totalBytes: Int64?
    var downloadRate: Int?
    var failureMessage: String?
    var audioLanguages: [String]?
    var subtitleLanguages: [String]?
    var audioTrackCount: Int?
    var subtitleTrackCount: Int?
    var trackInfoVerified: Bool?
    var trackInfoVersion: Int?

    init(
        id: UUID = UUID(),
        item: CatalogItem,
        episode: CatalogEpisode?,
        infoHash: String,
        torrentTitle: String,
        language: String? = nil,
        quality: String? = nil,
        audioLanguages: [String] = [],
        subtitleLanguages: [String] = []
    ) {
        self.id = id
        self.catalogID = item.id
        self.contentType = item.cinemetaType ?? .movie
        self.episodeID = episode?.id
        self.infoHash = infoHash.lowercased()
        self.torrentTitle = torrentTitle
        self.catalogItem = item
        self.language = language
        self.quality = quality
        self.folderRelativePath = Self.folderPath(for: item, episode: episode, versionID: id)
        self.videoRelativePath = nil
        self.status = .queued
        self.magnetURI = nil
        self.audioLanguages = audioLanguages
        self.subtitleLanguages = subtitleLanguages
        self.trackInfoVerified = nil
    }

    private static func folderPath(for item: CatalogItem, episode: CatalogEpisode?, versionID: UUID) -> String {
        let catalogID = safePathComponent(item.id)
        if item.cinemetaType == .series {
            let season = episode?.season ?? 0
            let episodeID = safePathComponent(episode?.id ?? "unknown")
            return "Series/\(catalogID)/Season-\(season)/\(episodeID)/\(versionID.uuidString)"
        }
        return "Movies/\(catalogID)/\(versionID.uuidString)"
    }

    private static func safePathComponent(_ value: String) -> String {
        let safe = value.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
                ? character : "_"
        }
        return String(safe).isEmpty ? "unknown" : String(safe)
    }
}

@MainActor
final class LocalMediaLibraryStore: ObservableObject {
    static let shared = LocalMediaLibraryStore()

    @Published private(set) var versions: [LocalMediaVersion] = []
    @Published private(set) var storageError: String?

    let rootURL: URL
    private let indexURL: URL
    private let fileManager = FileManager.default

    private init() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        rootURL = documentsURL.appending(path: "Orzen", directoryHint: .isDirectory)
        indexURL = rootURL.appending(path: "library.json")

        #if os(macOS)
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: indexURL.path) {
                let data = try Data(contentsOf: indexURL)
                versions = try JSONDecoder().decode([LocalMediaVersion].self, from: data)
            } else {
                try persist()
            }
        } catch {
            storageError = error.localizedDescription
        }
        #endif
    }

    func availableVersions(for item: CatalogItem, episode: CatalogEpisode?) -> [LocalMediaVersion] {
        versions.filter { version in
            version.catalogID == item.id
                && version.contentType == item.cinemetaType
                && version.episodeID == episode?.id
                && version.status == .completed
                && version.videoRelativePath.flatMap { relativePath in
                    fileManager.fileExists(atPath: rootURL.appending(path: relativePath).path)
                } == true
        }
    }

    @discardableResult
    func reserveVersion(
        for item: CatalogItem,
        episode: CatalogEpisode?,
        infoHash: String,
        torrentTitle: String,
        language: String? = nil,
        quality: String? = nil,
        audioLanguages: [String] = [],
        subtitleLanguages: [String] = []
    ) throws -> LocalMediaVersion {
        let version = LocalMediaVersion(
            item: item,
            episode: episode,
            infoHash: infoHash,
            torrentTitle: torrentTitle,
            language: language,
            quality: quality,
            audioLanguages: audioLanguages,
            subtitleLanguages: subtitleLanguages
        )
        let folderURL = rootURL.appending(path: version.folderRelativePath, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        versions.append(version)
        do {
            try persist()
        } catch {
            versions.removeAll { $0.id == version.id }
            throw error
        }
        return version
    }

    func update(_ version: LocalMediaVersion) throws {
        guard let index = versions.firstIndex(where: { $0.id == version.id }) else { return }
        let previous = versions[index]
        versions[index] = version
        do {
            try persist()
        } catch {
            versions[index] = previous
            throw error
        }
    }

    func fileURL(for version: LocalMediaVersion) -> URL? {
        guard let relativePath = version.videoRelativePath else { return nil }
        return rootURL.appending(path: relativePath)
    }

    func remove(_ version: LocalMediaVersion) throws {
        versions.removeAll { $0.id == version.id }
        try persist()
        try fileManager.removeItem(at: rootURL.appending(path: version.folderRelativePath))
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(versions)
        try data.write(to: indexURL, options: .atomic)
        storageError = nil
    }
}
