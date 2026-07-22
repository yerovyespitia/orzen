import Foundation
@testable import Orzen

enum TestFixtures {
    static func source(
        id: String = "source-1",
        addonName: String = "Test Addon",
        title: String = "Test Source",
        description: String = "Test source description",
        metadata: [String] = [],
        compatibilityHints: [String] = [],
        category: StreamSourceCategory = .general,
        addonSourceIndex: Int? = nil,
        url: URL? = URL(string: "https://example.com/video.m3u8"),
        torrentInfoHash: String? = nil
    ) -> StreamSource {
        StreamSource(
            id: id,
            addonName: addonName,
            title: title,
            description: description,
            metadata: metadata,
            compatibilityHints: compatibilityHints,
            sourceCategory: category,
            addonSourceIndex: addonSourceIndex,
            playbackURL: url,
            torrentInfoHash: torrentInfoHash
        )
    }

    static func item(
        id: String = "item-1",
        title: String = "Test Item",
        type: CinemetaType = .movie
    ) -> CatalogItem {
        CatalogItem(
            id: id,
            title: title,
            description: "Test item description",
            cinemetaType: type
        )
    }

    static func episode(
        id: String,
        season: Int = 1,
        number: Int,
        title: String? = nil
    ) -> CatalogEpisode {
        CatalogEpisode(
            id: id,
            title: title ?? "Episode \(number)",
            description: nil,
            thumbnailURL: nil,
            runtime: "45 min",
            released: nil,
            season: season,
            episode: number
        )
    }

    static func request(
        source: StreamSource = source(),
        item: CatalogItem? = item(),
        episode: CatalogEpisode? = nil,
        contentID: String = "item-1",
        contentType: CinemetaType = .movie,
        preferredSourceTitle: String? = nil,
        initialTrackSelections: PlaybackTrackSelections? = nil,
        attemptedSourceIDs: Set<StreamSource.ID> = []
    ) -> StreamPlaybackRequest {
        StreamPlaybackRequest(
            source: source,
            title: episode?.playbackTitle ?? item?.title ?? "Test",
            subtitle: item?.title ?? "Test",
            contentID: contentID,
            contentType: contentType,
            item: item,
            episode: episode,
            preferredSourceTitle: preferredSourceTitle,
            initialTrackSelections: initialTrackSelections,
            attemptedSourceIDs: attemptedSourceIDs
        )
    }

    static func track(
        id: String,
        title: String,
        language: String? = nil,
        kind: PlayerMediaTrack.Kind,
        isSelected: Bool = false,
        isOff: Bool = false,
        externalSubtitleID: String? = nil
    ) -> PlayerMediaTrack {
        PlayerMediaTrack(
            id: id,
            title: title,
            language: language,
            kind: kind,
            isSelected: isSelected,
            isOff: isOff,
            externalSubtitleID: externalSubtitleID
        )
    }

    static func isolatedDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "OrzenTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
