import Foundation

enum StreamPlayerPlatform {
    case macOS
    case iOS
}

enum StreamPlayerInitialPlaybackDecision: Equatable {
    case failure(String)
    case play(URL, with: StreamPlaybackEngine)
}

struct StreamPlayerFallbackSelection: Equatable {
    let source: StreamSource
    let attemptedSourceIDs: Set<StreamSource.ID>
}

enum StreamPlayerPlaybackPolicy {
    static func initialDecision(
        for source: StreamSource,
        platform: StreamPlayerPlatform,
        isVLCAvailable: Bool
    ) -> StreamPlayerInitialPlaybackDecision {
        if let playbackURLError = source.playbackURLError {
            return .failure(playbackURLError)
        }

        guard let playbackURL = source.playbackURL else {
            return .failure(
                "This source does not expose a direct video URL. The native player can only open direct HTTP or HTTPS video streams returned by the addon."
            )
        }

        switch platform {
        case .macOS:
            let engine: StreamPlaybackEngine = source.preferredPlaybackEngine == .native ? .native : .mpv
            return .play(playbackURL, with: engine)
        case .iOS:
            return .play(playbackURL, with: isVLCAvailable ? .vlc : .native)
        }
    }

    static func fallbackSelection(
        currentSource: StreamSource,
        previouslyAttemptedSourceIDs: Set<StreamSource.ID>,
        candidates: [StreamSource]
    ) -> StreamPlayerFallbackSelection? {
        var attemptedSourceIDs = previouslyAttemptedSourceIDs
        attemptedSourceIDs.insert(currentSource.id)

        let eligibleSources = candidates.filter { source in
            !attemptedSourceIDs.contains(source.id)
                && NativePlaybackCompatibilityResolver.compatibility(for: source).canAttemptPlayback
        }

        guard let source = NativePlaybackCompatibilityResolver.bestNativeSource(in: eligibleSources) else {
            return nil
        }

        return StreamPlayerFallbackSelection(
            source: source,
            attemptedSourceIDs: attemptedSourceIDs
        )
    }
}

enum StreamPlayerProgressAction: Equatable {
    case ignore
    case clear
    case complete
    case save
}

enum StreamPlayerProgressPolicy {
    static let minimumCompletableMovieDuration = 20 * 60.0
    static let minimumCompletableEpisodeDuration = 5 * 60.0

    static func canComplete(duration: Double, contentType: CinemetaType) -> Bool {
        guard duration.isFinite else { return false }

        switch contentType {
        case .movie:
            return duration >= minimumCompletableMovieDuration
        case .series:
            return duration >= minimumCompletableEpisodeDuration
        }
    }

    static func hasReachedPlaybackEnd(currentTime: Double, duration: Double) -> Bool {
        guard currentTime.isFinite,
              duration.isFinite,
              duration > 0 else {
            return false
        }

        return max(duration - currentTime, 0) <= 1.25
    }

    static func resumePositionToApply(
        hasAppliedSavedProgress: Bool,
        pendingResumePosition: Double?,
        hasActivePlaybackEngine: Bool,
        duration: Double
    ) -> Double? {
        guard !hasAppliedSavedProgress,
              let pendingResumePosition,
              hasActivePlaybackEngine,
              duration > 0,
              pendingResumePosition < max(duration - 5, 0) else {
            return nil
        }

        return pendingResumePosition
    }

    static func action(
        hasCompletedCurrentContent: Bool,
        hasActivePlaybackEngine: Bool,
        hasPlaybackError: Bool,
        currentTime: Double,
        duration: Double,
        contentType: CinemetaType,
        progressStoreConsidersComplete: Bool,
        pendingResumePosition: Double?,
        hasAppliedSavedProgress: Bool,
        lastSavedProgressPosition: Double,
        force: Bool
    ) -> StreamPlayerProgressAction {
        guard !hasCompletedCurrentContent,
              hasActivePlaybackEngine,
              !hasPlaybackError,
              currentTime.isFinite,
              duration.isFinite else {
            return .ignore
        }

        let canCompletePlayback = canComplete(duration: duration, contentType: contentType)

        if progressStoreConsidersComplete, canCompletePlayback {
            return .complete
        }

        if duration > 0, !canCompletePlayback {
            return .clear
        }

        if hasReachedPlaybackEnd(currentTime: currentTime, duration: duration), !canCompletePlayback {
            return .ignore
        }

        if let pendingResumePosition,
           !hasAppliedSavedProgress,
           currentTime < pendingResumePosition {
            return .ignore
        }

        guard force || abs(currentTime - lastSavedProgressPosition) >= 1 else {
            return .ignore
        }

        return .save
    }
}

enum StreamPlayerTrackPolicy {
    static func matchingTrack(
        for choice: PlaybackTrackChoice,
        in tracks: [PlayerMediaTrack]
    ) -> PlayerMediaTrack? {
        tracks.first { $0.id == choice.id }
            ?? tracks.first {
                $0.isOff == choice.isOff
                    && $0.language == choice.language
                    && $0.title == choice.title
            }
    }

    static func externalSubtitleTrackID(for subtitle: ExternalSubtitleTrack) -> String {
        "external-subtitle-\(subtitle.id)"
    }

    static func selectedTrackChoice(
        from tracks: [PlayerMediaTrack],
        kind: PlayerMediaTrack.Kind
    ) -> PlaybackTrackChoice? {
        guard let track = tracks.first(where: { $0.kind == kind && $0.isSelected }) else {
            return nil
        }

        return trackChoice(from: track)
    }

    static func trackChoice(from track: PlayerMediaTrack) -> PlaybackTrackChoice {
        PlaybackTrackChoice(
            id: track.id,
            title: track.title,
            language: track.language,
            isOff: track.isOff
        )
    }
}
