import Foundation

extension StreamPlayerView {
    func applySavedProgressIfPossible() {
        guard let resumePosition = StreamPlayerProgressPolicy.resumePositionToApply(
            hasAppliedSavedProgress: hasAppliedSavedProgress,
            pendingResumePosition: pendingResumePosition,
            hasActivePlaybackEngine: activePlaybackEngine != nil,
            duration: duration
        ) else {
            return
        }

        hasAppliedSavedProgress = true
        seek(to: resumePosition)
    }

    func saveCurrentProgress(
        force: Bool = false,
        trackSelections: PlaybackTrackSelections? = nil
    ) {
        let action = StreamPlayerProgressPolicy.action(
            hasCompletedCurrentContent: hasCompletedCurrentContent,
            hasActivePlaybackEngine: activePlaybackEngine != nil,
            hasPlaybackError: playbackErrorMessage != nil,
            currentTime: currentTime,
            duration: duration,
            contentType: request.contentType,
            progressStoreConsidersComplete: progressStore.isComplete(
                position: currentTime,
                duration: duration,
                contentType: request.contentType
            ),
            pendingResumePosition: pendingResumePosition,
            hasAppliedSavedProgress: hasAppliedSavedProgress,
            lastSavedProgressPosition: lastSavedProgressPosition,
            force: force
        )

        switch action {
        case .complete:
            completeCurrentContent()
            return
        case .clear:
            clearCurrentPlaybackProgress()
            return
        case .ignore:
            return
        case .save:
            break
        }

        progressStore.saveProgress(
            for: request,
            position: currentTime,
            duration: duration,
            trackSelections: trackSelections ?? currentTrackSelections,
            subtitleDelay: subtitleDelay,
            force: force
        )
        lastSavedProgressPosition = currentTime
    }

    func saveProgressOnDisappearIfNeeded() {
        let activeRequestID = StreamPlaybackStore.shared.request?.id
        guard activeRequestID == request.id else { return }
        saveCurrentProgress(force: true)
    }

    func completeCurrentContent() {
        guard !hasCompletedCurrentContent,
              canCompleteCurrentPlayback else {
            return
        }
        hasCompletedCurrentContent = true

        guard let item = request.item else {
            progressStore.clearProgress(contentID: request.contentID, contentType: request.contentType)
            return
        }

        let pendingNextEpisode = nextEpisode
        let trackSelections = currentTrackSelections

        switch request.contentType {
        case .movie:
            collectionStore.setWatched(item, isWatched: true)
        case .series:
            if let episode = request.episode {
                episodeWatchStore.markWatched(episode, in: item)
            }
            collectionStore.setDropped(item, isDropped: false)
            collectionStore.setWatched(item, isWatched: episodeWatchStore.isStoredSeriesFullyWatched(item))
            savePendingNextEpisodeProgress(
                pendingNextEpisode,
                in: item,
                trackSelections: trackSelections
            )
        }

        progressStore.clearProgress(contentID: request.contentID, contentType: request.contentType)
        chromeVisibility.keepVisible()
    }

    func handlePlaybackEnded() {
        guard !hasHandledPlaybackEnd else { return }
        hasHandledPlaybackEnd = true

        guard canCompleteCurrentPlayback else {
            clearCurrentPlaybackProgress()
            chromeVisibility.keepVisible()
            return
        }

        completeCurrentContent()

        guard request.contentType == .series,
              nextEpisode != nil else {
            return
        }

        playNextEpisode()
    }

    func handlePlaybackEndIfNeeded() {
        guard hasReachedPlaybackEnd else { return }
        handlePlaybackEnded()
    }

    var hasReachedPlaybackEnd: Bool {
        StreamPlayerProgressPolicy.hasReachedPlaybackEnd(
            currentTime: currentTime,
            duration: duration
        )
    }

    var canCompleteCurrentPlayback: Bool {
        StreamPlayerProgressPolicy.canComplete(
            duration: duration,
            contentType: request.contentType
        )
    }

    func clearCurrentPlaybackProgress() {
        progressStore.clearProgress(contentID: request.contentID, contentType: request.contentType)
    }

    func savePendingNextEpisodeProgress(
        _ episode: CatalogEpisode?,
        in item: CatalogItem,
        trackSelections: PlaybackTrackSelections
    ) {
        guard let episode,
              !episodeWatchStore.isStoredSeriesFullyWatched(item) else {
            return
        }

        let source = prefetchedSource(for: episode) ?? request.source
        progressStore.savePendingProgress(
            for: item,
            episode: episode,
            source: source,
            preferredSourceTitle: request.preferredSourceTitle,
            subtitle: item.title,
            trackSelections: trackSelections,
            subtitleDelay: subtitleDelay
        )

        guard prefetchedSource(for: episode) == nil else { return }

        Task {
            guard let refreshedSource = await nextSource(for: episode) else { return }
            await MainActor.run {
                progressStore.savePendingProgress(
                    for: item,
                    episode: episode,
                    source: refreshedSource,
                    preferredSourceTitle: request.preferredSourceTitle,
                    subtitle: item.title,
                    trackSelections: trackSelections,
                    subtitleDelay: subtitleDelay
                )
            }
        }
    }
}
