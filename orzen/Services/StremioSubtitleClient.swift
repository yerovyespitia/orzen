import Foundation

struct ExternalSubtitleTrack: Identifiable, Hashable, Sendable {
    let id: String
    let addonName: String
    let title: String
    let language: String?
    let url: URL
}

enum StremioSubtitleClient {
    static func fetchSubtitles(
        from addon: LocalAddon,
        type: CinemetaType,
        id: String,
        allowedLanguageCodes: Set<String>
    ) async throws -> [ExternalSubtitleTrack] {
        guard addon.supports(resource: .subtitles, type: type, id: id) else {
            return []
        }

        let url = subtitlesURL(from: addon.manifestURL, type: type, id: id)
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let subtitleResponse = try JSONDecoder().decode(StremioSubtitleResponse.self, from: data)
        return limitedSubtitles(
            from: subtitleResponse.subtitles,
            addon: addon,
            allowedLanguageCodes: allowedLanguageCodes
        )
    }

    private static func subtitlesURL(from manifestURL: URL, type: CinemetaType, id: String) -> URL {
        var baseURL = manifestURL
        if baseURL.lastPathComponent == "manifest.json" {
            baseURL.deleteLastPathComponent()
        }

        return baseURL
            .appending(path: "subtitles")
            .appending(path: type.rawValue)
            .appending(path: id)
            .appendingPathExtension("json")
    }

    private static func limitedSubtitles(
        from subtitles: [StremioSubtitle],
        addon: LocalAddon,
        allowedLanguageCodes: Set<String>
    ) -> [ExternalSubtitleTrack] {
        var countsByLanguage: [String: Int] = [:]

        return subtitles.compactMap { subtitle in
            guard let url = subtitle.url else { return nil }

            let languageKey = subtitle.lang?.lowercased() ?? "und"
            guard allowedLanguageCodes.contains(languageKey) else {
                return nil
            }

            let languageCount = (countsByLanguage[languageKey] ?? 0) + 1
            guard languageCount <= 4 else { return nil }

            countsByLanguage[languageKey] = languageCount
            let languageName = PlayerTrackLanguageName.displayName(for: subtitle.lang)
            let title = languageName.map { "\($0) \(languageCount)" } ?? "Subtitle \(languageCount)"

            return ExternalSubtitleTrack(
                id: "\(addon.id.uuidString)-\(subtitle.id)",
                addonName: addon.name,
                title: title,
                language: subtitle.lang,
                url: url
            )
        }
    }
}

private struct StremioSubtitleResponse: Decodable {
    let subtitles: [StremioSubtitle]
}

private struct StremioSubtitle: Decodable {
    let id: String
    let url: URL?
    let lang: String?
}
