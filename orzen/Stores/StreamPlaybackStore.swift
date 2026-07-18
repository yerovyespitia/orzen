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
        attemptedSourceIDs: Set<StreamSource.ID> = []
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
    }

    var id: String {
        "\(source.id)-\(title)-\(subtitle)-\(contentType.rawValue)-\(contentID)"
    }
}

@MainActor
final class StreamPlaybackStore: ObservableObject {
    static let shared = StreamPlaybackStore()

    @Published var request: StreamPlaybackRequest?

    private init() { }
}
