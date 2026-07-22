import AVFoundation

extension StreamPlayerView {
    func loadExternalSubtitles() async {
        guard !addonStore.subtitleAddons.isEmpty else {
            externalSubtitleTracks = []
            clearExternalSubtitleSelection()
            return
        }

        let loadedSubtitles = await ExternalSubtitleResolver.fetchSubtitles(
            from: addonStore.subtitleAddons,
            type: request.contentType,
            id: request.contentID,
            allowedLanguageCodes: subtitlePreferences.selectedLanguageCodes
        )

        externalSubtitleTracks = loadedSubtitles
        if let selectedExternalSubtitleID,
           !loadedSubtitles.contains(where: { $0.id == selectedExternalSubtitleID }) {
            clearExternalSubtitleSelection()
        }
    }


    func selectAudioTrack(_ track: PlayerMediaTrack) {
        performPlayerAction {
            switch activePlaybackEngine {
            case .mpv:
                mpvController.selectAudioTrack(track)
            case .vlc:
                #if os(iOS)
                vlcController.selectAudioTrack(track)
                #endif
            case .native:
                selectNativeTrack(track, characteristic: .audible)
            case nil:
                break
            }

            let updatedSelections = PlaybackTrackSelections(
                audio: trackChoice(from: track),
                subtitle: currentTrackSelections.subtitle
            )
            pendingTrackSelections = updatedSelections
            appliedSavedAudioTrackID = track.id
            saveCurrentProgress(force: true, trackSelections: updatedSelections)
        }
    }

    func selectSubtitleTrack(_ track: PlayerMediaTrack) {
        performPlayerAction {
            switch activePlaybackEngine {
            case .mpv:
                if let externalSubtitleID = track.externalSubtitleID {
                    selectedExternalSubtitleID = externalSubtitleID
                    mpvController.setSubtitleDelay(subtitleDelay)
                } else {
                    clearExternalSubtitleSelection()
                    mpvController.setSubtitleDelay(0)
                }
                mpvController.selectSubtitleTrack(track)
            case .vlc:
                #if os(iOS)
                selectVLCSubtitleTrack(track)
                #endif
            case .native:
                selectNativeSubtitleTrack(track)
            case nil:
                break
            }

            let updatedSelections = PlaybackTrackSelections(
                audio: currentTrackSelections.audio,
                subtitle: trackChoice(from: track)
            )
            pendingTrackSelections = updatedSelections
            appliedSavedSubtitleTrackID = track.id
            saveCurrentProgress(force: true, trackSelections: updatedSelections)
        }
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

    func applySavedTrackSelectionsIfPossible() {
        guard let pendingTrackSelections, activePlaybackEngine != nil else { return }

        if let audioChoice = pendingTrackSelections.audio,
           appliedSavedAudioTrackID != audioChoice.id,
           let audioTrack = matchingTrack(for: audioChoice, in: audioTracks) {
            selectStoredTrack(audioTrack)
            appliedSavedAudioTrackID = audioChoice.id
        }

        if let subtitleChoice = pendingTrackSelections.subtitle,
           appliedSavedSubtitleTrackID != subtitleChoice.id,
           let subtitleTrack = matchingTrack(for: subtitleChoice, in: subtitleTracks) {
            selectStoredTrack(subtitleTrack)
            appliedSavedSubtitleTrackID = subtitleChoice.id
        }
    }

    func selectStoredTrack(_ track: PlayerMediaTrack) {
        switch activePlaybackEngine {
        case .mpv:
            if track.kind == .audio {
                mpvController.selectAudioTrack(track)
            } else {
                mpvController.selectSubtitleTrack(track)
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

    func matchingTrack(for choice: PlaybackTrackChoice, in tracks: [PlayerMediaTrack]) -> PlayerMediaTrack? {
        StreamPlayerTrackPolicy.matchingTrack(for: choice, in: tracks)
    }

    func externalSubtitleTrackID(for subtitle: ExternalSubtitleTrack) -> String {
        StreamPlayerTrackPolicy.externalSubtitleTrackID(for: subtitle)
    }

    func selectedTrackChoice(from tracks: [PlayerMediaTrack], kind: PlayerMediaTrack.Kind) -> PlaybackTrackChoice? {
        StreamPlayerTrackPolicy.selectedTrackChoice(from: tracks, kind: kind)
    }

    func trackChoice(from track: PlayerMediaTrack) -> PlaybackTrackChoice {
        StreamPlayerTrackPolicy.trackChoice(from: track)
    }
}
