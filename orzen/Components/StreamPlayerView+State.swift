import SwiftUI
#if os(iOS)
import UIKit
#endif

extension StreamPlayerView {
    var isPaused: Bool {
        #if os(iOS)
        if activePlaybackEngine == .vlc {
            return vlcController.isPaused
        }
        #endif
        return activePlaybackEngine == .mpv ? mpvController.isPaused : nativeIsPaused
    }

    var currentTime: Double {
        #if os(iOS)
        if activePlaybackEngine == .vlc {
            return vlcController.currentTime
        }
        #endif
        return activePlaybackEngine == .mpv ? mpvController.currentTime : nativeTime
    }

    var duration: Double {
        #if os(iOS)
        if activePlaybackEngine == .vlc {
            return vlcController.duration
        }
        #endif
        return activePlaybackEngine == .mpv ? mpvController.duration : nativeDuration
    }

    var volume: Double {
        #if os(iOS)
        if activePlaybackEngine == .vlc {
            return vlcController.volume
        }
        #endif
        return activePlaybackEngine == .mpv ? mpvController.volume : nativeVolume
    }

    var isMuted: Bool {
        #if os(iOS)
        if activePlaybackEngine == .vlc {
            return vlcController.isMuted
        }
        #endif
        return activePlaybackEngine == .mpv ? mpvController.isMuted : nativeIsMuted
    }

    var audioTracks: [PlayerMediaTrack] {
        #if os(iOS)
        if activePlaybackEngine == .vlc {
            return vlcController.audioTracks
        }
        #endif
        return activePlaybackEngine == .mpv ? mpvController.audioTracks : nativeAudioTracks
    }

    var subtitleTracks: [PlayerMediaTrack] {
        switch activePlaybackEngine {
        case .mpv:
            return mpvController.subtitleTracks
        case .vlc:
            #if os(iOS)
            return vlcSubtitleTracksWithExternalSubtitles
            #else
            return []
            #endif
        case .native:
            #if os(iOS)
            return nativeSubtitleTracksWithExternalSubtitles
            #else
            return nativeSubtitleTracks
            #endif
        case nil:
            return nativeSubtitleTracks
        }
    }

    var nativeSubtitleTracksWithExternalSubtitles: [PlayerMediaTrack] {
        let nativeTracks = nativeSubtitleTracks.map { track in
            var updatedTrack = track
            if track.isOff {
                updatedTrack.isSelected = selectedExternalSubtitleID == nil && track.isSelected
            } else if selectedExternalSubtitleID != nil {
                updatedTrack.isSelected = false
            }
            return updatedTrack
        }

        let externalTracks = externalSubtitleTracks.map { subtitle in
            PlayerMediaTrack(
                id: externalSubtitleTrackID(for: subtitle),
                title: "\(subtitle.addonName): \(subtitle.title)",
                language: subtitle.language,
                kind: .subtitle,
                isSelected: selectedExternalSubtitleID == subtitle.id,
                isOff: false,
                externalSubtitleID: subtitle.id
            )
        }

        return nativeTracks + externalTracks
    }

    #if os(iOS)
    var vlcSubtitleTracksWithExternalSubtitles: [PlayerMediaTrack] {
        let vlcTracks = vlcController.subtitleTracks.map { track in
            var updatedTrack = track
            if track.isOff {
                updatedTrack.isSelected = selectedExternalSubtitleID == nil && track.isSelected
            } else if selectedExternalSubtitleID != nil {
                updatedTrack.isSelected = false
            }
            return updatedTrack
        }

        let externalTracks = externalSubtitleTracks.map { subtitle in
            PlayerMediaTrack(
                id: externalSubtitleTrackID(for: subtitle),
                title: "\(subtitle.addonName): \(subtitle.title)",
                language: subtitle.language,
                kind: .subtitle,
                isSelected: selectedExternalSubtitleID == subtitle.id,
                isOff: false,
                externalSubtitleID: subtitle.id
            )
        }

        return vlcTracks + externalTracks
    }
    #endif

    var currentExternalSubtitleText: String? {
        guard selectedExternalSubtitleID != nil,
              activePlaybackEngine == .native || activePlaybackEngine == .vlc else {
            return nil
        }

        return ExternalSubtitleResolver.preferredText(
            in: externalSubtitleCues,
            at: currentTime - subtitleDelay
        )
    }

    func setSubtitleDelay(_ delay: Double) {
        guard selectedExternalSubtitleID != nil else { return }
        subtitleDelay = min(max(delay, -10), 10)
        if activePlaybackEngine == .mpv {
            mpvController.setSubtitleDelay(subtitleDelay)
        }
        saveCurrentProgress(force: true)
        chromeVisibility.keepVisible()
    }

    var playbackErrorMessage: String? {
        switch activePlaybackEngine {
        #if os(macOS)
        case .mpv:
            return mpvController.errorMessage
        #else
        case .mpv:
            return playbackObserver.errorMessage
        #endif
        case .vlc:
            #if os(iOS)
            return vlcController.errorMessage
            #else
            return playbackObserver.errorMessage
            #endif
        case .native:
            return playbackObserver.errorMessage
        case nil:
            return playbackObserver.errorMessage ?? mpvController.errorMessage
        }
    }

    var isPreparingPlayback: Bool {
        #if os(iOS)
        if activePlaybackEngine == .vlc {
            return vlcController.isStarting
        }
        #endif
        return isPreparingNativePlayback || (activePlaybackEngine == .mpv && mpvController.isStarting)
    }

    var isChromePresented: Bool {
        chromeVisibility.isVisible || playbackErrorMessage != nil
    }

    var shouldAutoHideChrome: Bool {
        !isPaused
            && playbackErrorMessage == nil
            && !isEpisodeSidebarPresented
            && !isAdjustingTimeline
    }

    #if os(iOS)
    var effectiveVideoScale: CGFloat {
        videoScale
    }

    var videoPinchGesture: some Gesture {
        MagnificationGesture()
            .onEnded { value in
                if value > 1.05 {
                    videoScale = expandedVideoScale
                } else if value < 0.95 {
                    videoScale = 1
                }
            }
    }
    #endif

    var currentTrackSelections: PlaybackTrackSelections {
        PlaybackTrackSelections(
            audio: selectedTrackChoice(from: audioTracks, kind: .audio),
            subtitle: selectedTrackChoice(from: subtitleTracks, kind: .subtitle)
        )
    }

    var nextEpisode: CatalogEpisode? {
        guard request.contentType == .series,
              let item = request.item,
              let episode = request.episode else {
            return nil
        }

        return episodeWatchStore.nextEpisode(after: episode, in: item)
    }

    var canShowEpisodeSidebar: Bool {
        request.contentType == .series && request.item != nil
    }

    var shouldShowNextEpisodeBanner: Bool {
        guard nextEpisode != nil,
              !isEpisodeSidebarPresented,
              playbackErrorMessage == nil,
              currentTime.isFinite,
              duration.isFinite,
              duration > 0 else {
            return false
        }

        return max(duration - currentTime, 0) <= 120
    }

    var nextEpisodeBannerBottomPadding: CGFloat {
        #if os(iOS)
        return isChromePresented ? 128 : 28
        #else
        return isChromePresented ? 92 : 28
        #endif
    }

    var appWillTerminateNotification: Notification.Name {
        #if os(iOS)
        return UIApplication.willTerminateNotification
        #else
        return NSApplication.willTerminateNotification
        #endif
    }
}
