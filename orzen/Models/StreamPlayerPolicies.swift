import Foundation

enum StreamPlayerPlatform {
    case macOS
    case iOS
}

enum StreamPlayerInitialPlaybackDecision: Equatable {
    case failure(String)
    case play(URL, with: StreamPlaybackEngine)
}

enum StreamPlayerForegroundAction: Equatable {
    case none
    case recoverVideoOutput(shouldResume: Bool, requiresTrackReset: Bool)
}

enum StreamPlayerLifecyclePolicy {
    static func foregroundAction(
        for engine: StreamPlaybackEngine?,
        wasPausedBeforeBackground: Bool?,
        hasEnteredBackground: Bool,
        isPictureInPictureActive: Bool
    ) -> StreamPlayerForegroundAction {
        guard engine == .vlc || engine == .native,
              let wasPausedBeforeBackground,
              hasEnteredBackground,
              !isPictureInPictureActive else {
            return .none
        }

        return .recoverVideoOutput(
            shouldResume: !wasPausedBeforeBackground,
            requiresTrackReset: wasPausedBeforeBackground
        )
    }
}

enum PausedVideoOutputRecoveryPolicy {
    static let minimumRecoveredPlaybackDuration = 0.75

    static func shouldComplete(
        force: Bool,
        hasVideoOutput: Bool,
        recoveredPlaybackDuration: Double
    ) -> Bool {
        force || (
            hasVideoOutput
                && recoveredPlaybackDuration >= minimumRecoveredPlaybackDuration
        )
    }
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
    static let maximumSelectionAttempts = 3
    private static let externalSubtitleTrackIDPrefix = "external-subtitle-"

    /// Resolves a saved choice against the tracks of the current engine.
    /// Addon subtitles are matched by their addon subtitle ID, never by the
    /// engine track ID: mpv numbers them in load order, which is not stable.
    /// Returns nil while an addon subtitle choice cannot be resolved yet.
    static func matchingTrack(
        for choice: PlaybackTrackChoice,
        in tracks: [PlayerMediaTrack],
        externalSubtitlesAreLoaded: Bool = true
    ) -> PlayerMediaTrack? {
        if choice.isOff {
            return tracks.first(where: \.isOff)
        }

        let candidates = tracks.filter { !$0.isOff }
        let externalSubtitleID = externalSubtitleID(for: choice)
        let externalAddonName = externalSubtitleAddonName(for: choice, in: candidates)

        if externalSubtitleID != nil || externalAddonName != nil {
            if let externalSubtitleID,
               let track = candidates.first(where: { $0.externalSubtitleID == externalSubtitleID }) {
                return track
            }

            guard externalSubtitlesAreLoaded else { return nil }

            // A different episode or a refreshed addon response: keep the same
            // addon and language instead of an unrelated embedded track.
            return candidates.first { track in
                track.externalSubtitleID != nil
                    && (externalAddonName == nil || track.externalSubtitleAddonName == externalAddonName)
                    && languagesMatch(track.language, choice.language)
            }
        }

        let embeddedTracks = candidates.filter { $0.externalSubtitleID == nil }
        if let track = embeddedTracks.first(where: {
            $0.id == choice.id && languagesMatch($0.language, choice.language)
        }) {
            return track
        }

        let sameLanguageTracks = embeddedTracks.filter { languagesMatch($0.language, choice.language) }
        if let languageOrdinal = choice.languageOrdinal,
           sameLanguageTracks.indices.contains(languageOrdinal) {
            return sameLanguageTracks[languageOrdinal]
        }

        if let track = sameLanguageTracks.first(where: { $0.title == choice.title }) {
            return track
        }

        return choice.language == nil ? nil : sameLanguageTracks.first
    }

    /// The track that must be selected to honor the requested choice, or nil
    /// when the choice is already in effect or cannot be resolved yet.
    static func trackToSelect(
        for choice: PlaybackTrackChoice,
        in tracks: [PlayerMediaTrack],
        externalSubtitlesAreLoaded: Bool
    ) -> PlayerMediaTrack? {
        guard let track = matchingTrack(
            for: choice,
            in: tracks,
            externalSubtitlesAreLoaded: externalSubtitlesAreLoaded
        ), !track.isSelected else {
            return nil
        }

        return track
    }

    /// Persists what the user asked for. The engine state is only a fallback,
    /// because engines auto-select default tracks and a saved choice may not
    /// be resolvable on this device yet.
    static func persistedSelections(
        requested: PlaybackTrackSelections?,
        engine: PlaybackTrackSelections
    ) -> PlaybackTrackSelections {
        PlaybackTrackSelections(
            audio: requested?.audio ?? engine.audio,
            subtitle: requested?.subtitle ?? engine.subtitle
        )
    }

    static func externalSubtitleTrackID(for subtitle: ExternalSubtitleTrack) -> String {
        "\(externalSubtitleTrackIDPrefix)\(subtitle.id)"
    }

    static func selectedTrackChoice(
        from tracks: [PlayerMediaTrack],
        kind: PlayerMediaTrack.Kind
    ) -> PlaybackTrackChoice? {
        guard let track = tracks.first(where: { $0.kind == kind && $0.isSelected }) else {
            return nil
        }

        return trackChoice(from: track, in: tracks)
    }

    static func trackChoice(
        from track: PlayerMediaTrack,
        in tracks: [PlayerMediaTrack] = []
    ) -> PlaybackTrackChoice {
        var choice = PlaybackTrackChoice(
            id: track.id,
            title: track.title,
            language: track.language,
            isOff: track.isOff,
            externalSubtitleID: track.externalSubtitleID,
            externalSubtitleAddonName: track.externalSubtitleAddonName
        )

        if !track.isOff, track.externalSubtitleID == nil {
            choice.languageOrdinal = tracks
                .filter {
                    $0.kind == track.kind
                        && !$0.isOff
                        && $0.externalSubtitleID == nil
                        && languagesMatch($0.language, track.language)
                }
                .firstIndex { $0.id == track.id }
        }

        return choice
    }

    static func languagesMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        PlayerTrackLanguageName.normalizedCode(for: lhs) == PlayerTrackLanguageName.normalizedCode(for: rhs)
    }

    private static func externalSubtitleID(for choice: PlaybackTrackChoice) -> String? {
        if let externalSubtitleID = choice.externalSubtitleID {
            return externalSubtitleID
        }

        // Choices saved before addon subtitle IDs were persisted on iOS.
        guard choice.id.hasPrefix(externalSubtitleTrackIDPrefix) else { return nil }
        return String(choice.id.dropFirst(externalSubtitleTrackIDPrefix.count))
    }

    private static func externalSubtitleAddonName(
        for choice: PlaybackTrackChoice,
        in tracks: [PlayerMediaTrack]
    ) -> String? {
        if let addonName = choice.externalSubtitleAddonName {
            return addonName
        }

        // Older choices only kept the "Addon: Title" display title.
        guard let separatorRange = choice.title.range(of: ": ") else { return nil }
        let prefix = String(choice.title[..<separatorRange.lowerBound])
        return tracks.contains { $0.externalSubtitleAddonName == prefix } ? prefix : nil
    }
}
