import Foundation

struct StreamPlaybackRequest: Identifiable {
    let source: StreamSource
    let title: String
    let subtitle: String
    let contentID: String
    let contentType: CinemetaType
    let item: CatalogItem?
    let episode: CatalogEpisode?
    let preferredSourceTitle: String
    let initialTrackSelections: PlaybackTrackSelections?
    let attemptedSourceIDs: Set<StreamSource.ID>
    let requiresSourceRefresh: Bool

    init(
        source: StreamSource,
        title: String,
        subtitle: String,
        contentID: String,
        contentType: CinemetaType,
        item: CatalogItem? = nil,
        episode: CatalogEpisode? = nil,
        preferredSourceTitle: String? = nil,
        initialTrackSelections: PlaybackTrackSelections? = nil,
        attemptedSourceIDs: Set<StreamSource.ID> = [],
        requiresSourceRefresh: Bool = false
    ) {
        self.source = source
        self.title = title
        self.subtitle = subtitle
        self.contentID = contentID
        self.contentType = contentType
        self.item = item
        self.episode = episode
        self.preferredSourceTitle = preferredSourceTitle ?? source.title
        self.initialTrackSelections = initialTrackSelections
        self.attemptedSourceIDs = attemptedSourceIDs
        self.requiresSourceRefresh = requiresSourceRefresh
    }

    var id: String {
        let playbackID = "\(source.id)-\(title)-\(subtitle)-\(contentType.rawValue)-\(contentID)"
        return requiresSourceRefresh ? "\(playbackID)-refreshing-source" : playbackID
    }

    func replacingSource(_ source: StreamSource) -> StreamPlaybackRequest {
        StreamPlaybackRequest(
            source: source,
            title: title,
            subtitle: subtitle,
            contentID: contentID,
            contentType: contentType,
            item: item,
            episode: episode,
            preferredSourceTitle: preferredSourceTitle,
            initialTrackSelections: initialTrackSelections,
            attemptedSourceIDs: attemptedSourceIDs
        )
    }

    func requiringSourceRefresh() -> StreamPlaybackRequest {
        StreamPlaybackRequest(
            source: source,
            title: title,
            subtitle: subtitle,
            contentID: contentID,
            contentType: contentType,
            item: item,
            episode: episode,
            preferredSourceTitle: preferredSourceTitle,
            initialTrackSelections: initialTrackSelections,
            attemptedSourceIDs: attemptedSourceIDs,
            requiresSourceRefresh: true
        )
    }

    func completingSourceRefresh(with source: StreamSource) -> StreamPlaybackRequest {
        replacingSource(source)
    }
}

@MainActor
final class StreamPlaybackStore: ObservableObject {
    static let shared = StreamPlaybackStore()

    @Published var request: StreamPlaybackRequest?

    private init() { }
}
