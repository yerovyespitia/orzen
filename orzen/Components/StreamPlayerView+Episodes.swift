import Foundation

extension StreamPlayerView {
    func playNextEpisode() {
        guard !isLoadingNextEpisode,
              let item = request.item,
              let nextEpisode else {
            return
        }

        isLoadingNextEpisode = true
        saveCurrentProgress(force: true)
        let trackSelections = currentTrackSelections

        Task {
            let source: StreamSource?
            if let prefetchedSource = prefetchedSource(for: nextEpisode) {
                source = prefetchedSource
            } else {
                source = await nextSource(for: nextEpisode)
            }

            await MainActor.run {
                isLoadingNextEpisode = false
                guard let source else { return }

                StreamPlaybackStore.shared.request = StreamPlaybackRequest(
                    source: source,
                    title: nextEpisode.playbackTitle,
                    subtitle: item.title,
                    contentID: nextEpisode.id,
                    contentType: .series,
                    item: item,
                    episode: nextEpisode,
                    preferredSourceTitle: request.preferredSourceTitle,
                    initialTrackSelections: trackSelections
                )
            }
        }
    }

    func prefetchNextSource() async {
        guard let nextEpisode else {
            prefetchedNextEpisodeID = nil
            prefetchedNextSource = nil
            return
        }

        prefetchedNextEpisodeID = nextEpisode.id
        prefetchedNextSource = nil
        let source = await nextSource(for: nextEpisode)
        guard prefetchedNextEpisodeID == nextEpisode.id else { return }
        prefetchedNextSource = source
    }

    func prefetchedSource(for episode: CatalogEpisode) -> StreamSource? {
        guard prefetchedNextEpisodeID == episode.id else { return nil }
        return prefetchedNextSource
    }

    func nextSource(for episode: CatalogEpisode) async -> StreamSource? {
        await StreamSourceResolver.continuingSource(
            after: request.source,
            preferredTitle: request.preferredSourceTitle,
            from: addonStore.streamAddons,
            type: .series,
            id: episode.id
        )
    }
}
