import AVFoundation

extension StreamPlayerView {
    func loadExternalSubtitles() async {
        guard !addonStore.subtitleAddons.isEmpty else {
            externalSubtitleTracks = []
            clearExternalSubtitleSelection()
            hasLoadedExternalSubtitles = true
            applySavedTrackSelectionsIfPossible()
            return
        }

        let loadedSubtitles = await ExternalSubtitleResolver.fetchSubtitles(
            from: addonStore.subtitleAddons,
            type: request.contentType,
            id: request.contentID,
            allowedLanguageCodes: subtitlePreferences.selectedLanguageCodes
        )

        externalSubtitleTracks = loadedSubtitles
        hasLoadedExternalSubtitles = true
        if let selectedExternalSubtitleID,
           !loadedSubtitles.contains(where: { $0.id == selectedExternalSubtitleID }) {
            clearExternalSubtitleSelection()
        }
        applySavedTrackSelectionsIfPossible()
    }


    func selectAudioTrack(_ track: PlayerMediaTrack) {
        performPlayerAction {
            let choice = trackChoice(from: track, in: audioTracks)
            selectStoredTrack(track)

            let updatedSelections = PlaybackTrackSelections(
                audio: choice,
                subtitle: currentTrackSelections.subtitle
            )
            pendingTrackSelections = updatedSelections
            resetTrackSelectionAttempts(for: .audio)
            saveCurrentProgress(force: true, trackSelections: updatedSelections)
        }
    }

    func selectSubtitleTrack(_ track: PlayerMediaTrack) {
        performPlayerAction {
            let choice = trackChoice(from: track, in: subtitleTracks)
            selectStoredTrack(track)

            let updatedSelections = PlaybackTrackSelections(
                audio: currentTrackSelections.audio,
                subtitle: choice
            )
            pendingTrackSelections = updatedSelections
            resetTrackSelectionAttempts(for: .subtitle)
            saveCurrentProgress(force: true, trackSelections: updatedSelections)
        }
    }

    func selectMPVSubtitleTrack(_ track: PlayerMediaTrack) {
        if let externalSubtitleID = track.externalSubtitleID {
            selectedExternalSubtitleID = externalSubtitleID
            mpvController.setSubtitleDelay(subtitleDelay)
        } else {
            clearExternalSubtitleSelection()
            mpvController.setSubtitleDelay(0)
        }
        mpvController.selectSubtitleTrack(track)
    }

    func selectNativeSubtitleTrack(_ track: PlayerMediaTrack) {
        if let externalSubtitleID = track.externalSubtitleID,
           let subtitle = externalSubtitleTracks.first(where: { $0.id == externalSubtitleID }) {
            selectedExternalSubtitleID = externalSubtitleID
            selectNativeTrack(NativePlayerTrackResolver.offTrack(kind: .subtitle, isSelected: true), characteristic: .legible)
            loadExternalSubtitleCues(for: subtitle)
            refreshNativeMediaTracks()
            return
        }

        clearExternalSubtitleSelection()
        selectNativeTrack(track, characteristic: .legible)
    }

    #if os(iOS)
    func selectVLCSubtitleTrack(_ track: PlayerMediaTrack) {
        if let externalSubtitleID = track.externalSubtitleID,
           let subtitle = externalSubtitleTracks.first(where: { $0.id == externalSubtitleID }) {
            selectedExternalSubtitleID = externalSubtitleID
            vlcController.selectSubtitleTrack(
                PlayerMediaTrack(
                    id: "vlc-subtitle-off",
                    title: "Off",
                    language: nil,
                    kind: .subtitle,
                    isSelected: true,
                    isOff: true
                )
            )
            loadExternalSubtitleCues(for: subtitle)
            return
        }

        clearExternalSubtitleSelection()
        vlcController.selectSubtitleTrack(track)
    }
    #endif

    func loadExternalSubtitleCues(for subtitle: ExternalSubtitleTrack) {
        loadingExternalSubtitleID = subtitle.id
        externalSubtitleCues = []

        Task {
            let loadedSubtitle = try? await ExternalSubtitleResolver.loadSubtitle(from: subtitle)

            await MainActor.run {
                guard loadingExternalSubtitleID == subtitle.id else { return }
                externalSubtitleCues = loadedSubtitle?.cues ?? []
                loadingExternalSubtitleID = nil
            }
        }
    }

    func clearExternalSubtitleSelection() {
        selectedExternalSubtitleID = nil
        loadingExternalSubtitleID = nil
        externalSubtitleCues = []
    }

    func ensureEmbeddedSubtitlesAreDisabled() {
        guard selectedExternalSubtitleID != nil else { return }

        switch activePlaybackEngine {
        case .native:
            guard nativeSubtitleTracks.contains(where: { !$0.isOff && $0.isSelected }) else {
                return
            }
            selectNativeTrack(
                NativePlayerTrackResolver.offTrack(kind: .subtitle, isSelected: true),
                characteristic: .legible
            )
        case .vlc:
            #if os(iOS)
            guard !vlcController.isRenderingExternalSubtitle else { return }
            guard vlcController.subtitleTracks.contains(where: { !$0.isOff && $0.isSelected }) else {
                return
            }
            vlcController.selectSubtitleTrack(
                PlayerMediaTrack(
                    id: "vlc-subtitle-off",
                    title: "Off",
                    language: nil,
                    kind: .subtitle,
                    isSelected: true,
                    isOff: true
                )
            )
            #endif
        case .mpv, nil:
            break
        }
    }


    func refreshNativeMediaTracks() {
        guard activePlaybackEngine == .native else { return }
        nativeAudioTracks = NativePlayerTrackResolver.tracks(
            in: player?.currentItem,
            for: .audible,
            kind: .audio,
            includesOffOption: false
        )
        nativeSubtitleTracks = NativePlayerTrackResolver.tracks(
            in: player?.currentItem,
            for: .legible,
            kind: .subtitle,
            includesOffOption: true
        )
    }

    func selectNativeTrack(_ track: PlayerMediaTrack, characteristic: AVMediaCharacteristic) {
        NativePlayerTrackResolver.select(track, in: player?.currentItem, for: characteristic)
        refreshNativeMediaTracks()
    }

    /// Keeps the requested tracks in effect. Engines may auto-select default
    /// tracks after a saved choice was first applied, so this runs on every
    /// track list change, with a bounded number of attempts per track.
    func applySavedTrackSelectionsIfPossible() {
        guard let pendingTrackSelections, activePlaybackEngine != nil else { return }

        if let audioChoice = pendingTrackSelections.audio {
            enforceTrackSelection(audioChoice, in: audioTracks)
        }

        if let subtitleChoice = pendingTrackSelections.subtitle {
            enforceTrackSelection(subtitleChoice, in: subtitleTracks)
        }
    }

    func enforceTrackSelection(_ choice: PlaybackTrackChoice, in tracks: [PlayerMediaTrack]) {
        guard let track = StreamPlayerTrackPolicy.trackToSelect(
            for: choice,
            in: tracks,
            externalSubtitlesAreLoaded: hasLoadedExternalSubtitles
        ) else {
            return
        }

        let attemptKey = "\(track.kind.rawValue):\(track.id)"
        let attempts = trackSelectionAttempts[attemptKey, default: 0]
        guard attempts < StreamPlayerTrackPolicy.maximumSelectionAttempts else { return }
        trackSelectionAttempts[attemptKey] = attempts + 1
        selectStoredTrack(track)
    }

    func resetTrackSelectionAttempts(for kind: PlayerMediaTrack.Kind) {
        trackSelectionAttempts = trackSelectionAttempts.filter { !$0.key.hasPrefix("\(kind.rawValue):") }
    }

    func selectStoredTrack(_ track: PlayerMediaTrack) {
        switch activePlaybackEngine {
        case .mpv:
            if track.kind == .audio {
                mpvController.selectAudioTrack(track)
            } else {
                selectMPVSubtitleTrack(track)
            }
        case .vlc:
            #if os(iOS)
            if track.kind == .audio {
                vlcController.selectAudioTrack(track)
            } else {
                selectVLCSubtitleTrack(track)
            }
            #endif
        case .native:
            if track.kind == .audio {
                selectNativeTrack(track, characteristic: .audible)
            } else {
                selectNativeSubtitleTrack(track)
            }
        case nil:
            break
        }
    }

    func externalSubtitleTrackID(for subtitle: ExternalSubtitleTrack) -> String {
        StreamPlayerTrackPolicy.externalSubtitleTrackID(for: subtitle)
    }

    func selectedTrackChoice(from tracks: [PlayerMediaTrack], kind: PlayerMediaTrack.Kind) -> PlaybackTrackChoice? {
        StreamPlayerTrackPolicy.selectedTrackChoice(from: tracks, kind: kind)
    }

    func trackChoice(from track: PlayerMediaTrack, in tracks: [PlayerMediaTrack]) -> PlaybackTrackChoice {
        StreamPlayerTrackPolicy.trackChoice(from: track, in: tracks)
    }
}
