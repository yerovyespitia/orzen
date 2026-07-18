import Foundation

struct StreamSource: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let addonName: String
    let title: String
    let description: String
    let metadata: [String]
    let compatibilityHints: [String]
    let sourceCategory: StreamSourceCategory
    let addonSourceIndex: Int?
    let playbackURL: URL?
    let torrentInfoHash: String?
    let torrentFileIndex: Int?

    init(
        id: String,
        addonName: String,
        title: String,
        description: String,
        metadata: [String],
        compatibilityHints: [String] = [],
        sourceCategory: StreamSourceCategory,
        addonSourceIndex: Int? = nil,
        playbackURL: URL?,
        torrentInfoHash: String? = nil,
        torrentFileIndex: Int? = nil
    ) {
        self.id = id
        self.addonName = addonName
        self.title = title
        self.description = description
        self.metadata = metadata
        self.compatibilityHints = compatibilityHints
        self.sourceCategory = sourceCategory
        self.addonSourceIndex = addonSourceIndex
        self.playbackURL = playbackURL
        self.torrentInfoHash = torrentInfoHash
        self.torrentFileIndex = torrentFileIndex
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case addonName
        case title
        case description
        case metadata
        case compatibilityHints
        case sourceCategory
        case addonSourceIndex
        case playbackURL
        case torrentInfoHash
        case torrentFileIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        addonName = try container.decode(String.self, forKey: .addonName)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        metadata = try container.decode([String].self, forKey: .metadata)
        compatibilityHints = try container.decodeIfPresent([String].self, forKey: .compatibilityHints) ?? []
        sourceCategory = try container.decode(StreamSourceCategory.self, forKey: .sourceCategory)
        addonSourceIndex = try container.decodeIfPresent(Int.self, forKey: .addonSourceIndex)
        playbackURL = try container.decodeIfPresent(URL.self, forKey: .playbackURL)
        torrentInfoHash = try container.decodeIfPresent(String.self, forKey: .torrentInfoHash)
        torrentFileIndex = try container.decodeIfPresent(Int.self, forKey: .torrentFileIndex)
    }

    var preferredPlaybackEngine: StreamPlaybackEngine {
        guard playbackURL != nil else { return .native }
        return .mpv
    }

    var playbackURLError: String? {
        guard let playbackURL else {
            if torrentInfoHash != nil {
                return "This source only exposes BitTorrent metadata. Orzen on iPhone needs a direct HTTP or HTTPS stream from a configured addon or debrid provider."
            }

            return "This source does not expose a direct video URL. Orzen can only open direct HTTP or HTTPS video streams returned by the addon."
        }

        guard ["http", "https"].contains(playbackURL.scheme?.lowercased()) else {
            return "This source uses an unsupported URL scheme: \(playbackURL.scheme ?? "unknown")."
        }

        return nil
    }

    var nativePlaybackError: String? {
        if let playbackURLError {
            return playbackURLError
        }

        let compatibility = NativePlaybackCompatibilityResolver.compatibility(for: self)
        guard !compatibility.canAttemptPlayback else {
            return nil
        }

        return compatibility.message
    }
}

struct StreamSourceCategory: Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let general = StreamSourceCategory(rawValue: "general")
    static let spanish = StreamSourceCategory.language("spanish")

    static func language(_ value: String) -> StreamSourceCategory {
        StreamSourceCategory(rawValue: "language:\(value)")
    }

    var filterTitle: String? {
        guard rawValue.hasPrefix("language:") else { return nil }
        let value = String(rawValue.dropFirst("language:".count))
        return value.replacingOccurrences(of: "-", with: " ").capitalized
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        // Migrate the category written by older versions of Orzen.
        rawValue = value == "spanish" ? "language:spanish" : value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum StreamPlaybackEngine: Sendable {
    case native
    case vlc
    case mpv
}

enum StremioStreamClient {
    static func fetchSources(
        from addon: LocalAddon,
        type: CinemetaType,
        id: String
    ) async throws -> [StreamSource] {
        guard addon.supports(resource: .stream, type: type, id: id) else {
            return []
        }

        let url = streamURL(from: addon.manifestURL, type: type, id: id)
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let streamResponse = try JSONDecoder().decode(StremioStreamResponse.self, from: data)
        return streamResponse.streams.enumerated().compactMap { index, stream in
            stream.source(
                addonName: addon.name,
                fallbackID: "\(addon.id.uuidString)-\(index)",
                addonSourceIndex: index,
                sourceCategory: addon.sourceCategory
            )
        }
    }

    private static func streamURL(from manifestURL: URL, type: CinemetaType, id: String) -> URL {
        var baseURL = manifestURL
        if baseURL.lastPathComponent == "manifest.json" {
            baseURL.deleteLastPathComponent()
        }

        return baseURL
            .appending(path: "stream")
            .appending(path: type.rawValue)
            .appending(path: id)
            .appendingPathExtension("json")
    }
}

private struct StremioStreamResponse: Decodable {
    let streams: [StremioStream]
}

private struct StremioStream: Decodable {
    let name: String?
    let title: String?
    let description: String?
    let url: URL?
    let externalUrl: URL?
    let infoHash: String?
    let fileIdx: Int?
    let behaviorHints: StremioStreamBehaviorHints?

    private enum CodingKeys: String, CodingKey {
        case name
        case title
        case description
        case url
        case externalUrl
        case infoHash
        case fileIdx
        case behaviorHints
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        url = Self.decodeURL(from: container, forKey: .url)
        externalUrl = Self.decodeURL(from: container, forKey: .externalUrl)
        infoHash = try container.decodeIfPresent(String.self, forKey: .infoHash)
        fileIdx = try container.decodeIfPresent(Int.self, forKey: .fileIdx)
        behaviorHints = try container.decodeIfPresent(StremioStreamBehaviorHints.self, forKey: .behaviorHints)
    }

    func source(
        addonName: String,
        fallbackID: String,
        addonSourceIndex: Int,
        sourceCategory: StreamSourceCategory
    ) -> StreamSource? {
        guard let directPlaybackURL else { return nil }

        let lines = (title ?? name ?? "Source")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let resolvedTitle = lines.first ?? name ?? "Source"
        let resolvedDescription = description ?? lines.dropFirst().joined(separator: "  ")
        let idParts = [fallbackID, infoHash, fileIdx.map(String.init), resolvedTitle]
            .compactMap { $0 }

        return StreamSource(
            id: idParts.joined(separator: "-"),
            addonName: addonName,
            title: resolvedTitle,
            description: resolvedDescription.isEmpty ? "No source details available." : resolvedDescription,
            metadata: metadata(addonName: addonName, titleLines: lines),
            compatibilityHints: compatibilityHints(titleLines: lines),
            sourceCategory: sourceCategory,
            addonSourceIndex: addonSourceIndex,
            playbackURL: directPlaybackURL,
            torrentInfoHash: infoHash,
            torrentFileIndex: fileIdx
        )
    }

    private var directPlaybackURL: URL? {
        [url, externalUrl].compactMap { $0 }.first { playbackURL in
            ["http", "https"].contains(playbackURL.scheme?.lowercased())
        }
    }

    private static func decodeURL(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> URL? {
        guard let rawValue = try? container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return nil }

        if let url = URL(string: trimmedValue) {
            return url
        }

        return trimmedValue.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
            .flatMap(URL.init(string:))
    }

    private func metadata(addonName: String, titleLines: [String]) -> [String] {
        var values = [addonName]

        if let quality = titleLines.first(where: { $0.range(of: #"(?i)\b(4k|2160p|1080p|720p|480p)\b"#, options: .regularExpression) != nil }) {
            values.append(quality)
        }

        if let seeders = titleLines.first(where: { $0.localizedCaseInsensitiveContains("seed") }) {
            values.append(seeders)
        }

        return values
    }

    private func compatibilityHints(titleLines: [String]) -> [String] {
        var values = titleLines
        if let name {
            values.append(name)
        }
        if let filename = behaviorHints?.filename {
            values.append(filename)
        }
        if let videoHash = behaviorHints?.videoHash {
            values.append(videoHash)
        }
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct StremioStreamBehaviorHints: Decodable {
    let filename: String?
    let videoHash: String?
}
