import AVKit
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct StreamPlayerView: View {
    let request: StreamPlaybackRequest
    let onBack: () -> Void

    @ObservedObject private var addonStore = LocalAddonStore.shared
    @ObservedObject private var subtitlePreferences = SubtitlePreferencesStore.shared
    @ObservedObject private var progressStore = PlaybackProgressStore.shared
    @ObservedObject private var collectionStore = CollectionStore.shared
    @ObservedObject private var episodeWatchStore = EpisodeWatchStore.shared
    @State private var player: AVPlayer?
    @State private var nativeTime: Double = 0
    @State private var nativeDuration: Double = 0
    @State private var nativeIsPaused = false
    @State private var nativeVolume: Double = 100
    @State private var nativeIsMuted = false
    @State private var nativeAudioTracks: [PlayerMediaTrack] = []
    @State private var nativeSubtitleTracks: [PlayerMediaTrack] = []
    @State private var externalSubtitleTracks: [ExternalSubtitleTrack] = []
    @State private var selectedExternalSubtitleID: String?
    @State private var externalSubtitleCues: [ExternalSubtitleCue] = []
    @State private var loadingExternalSubtitleID: String?
    @State private var subtitleDelay: Double = 0
    @State private var nativeTimeObserver: Any?
    @State private var isPreparingNativePlayback = false
    @State private var isResolvingNativeFallback = false
    @State private var nativeStartupTimeoutWorkItem: DispatchWorkItem?
    @State private var isFullscreen = false
    @State private var isClosing = false
    @State private var shouldBackAfterFullscreenExit = false
    @State private var activePlaybackEngine: StreamPlaybackEngine?
    @State private var pendingResumePosition: Double?
    @State private var pendingTrackSelections: PlaybackTrackSelections?
    @State private var hasAppliedSavedProgress = false
    @State private var appliedSavedAudioTrackID: String?
    @State private var appliedSavedSubtitleTrackID: String?
    @State private var lastSavedProgressPosition: Double = 0
    @State private var hasCompletedCurrentContent = false
    @State private var hasHandledPlaybackEnd = false
    @State private var isLoadingNextEpisode = false
    @State private var isEpisodeSidebarPresented = false
    @State private var isAdjustingTimeline = false
    @State private var prefetchedNextEpisodeID: CatalogEpisode.ID?
    @State private var prefetchedNextSource: StreamSource?
    @StateObject private var playbackObserver = StreamPlaybackObserver()
    #if os(iOS)
    @StateObject private var vlcController = VLCPlaybackController()
    #endif
    @StateObject private var mpvController = MPVPlaybackController()
    @StateObject private var chromeVisibility = StreamPlayerChromeVisibilityController()
    #if os(iOS)
    @State private var videoScale: CGFloat = 1
    #endif

    private let nativeStartupMinimumProgress = 1.0
    private let minimumCompletableMovieDuration = 20 * 60.0
    private let minimumCompletableEpisodeDuration = 5 * 60.0
    #if os(iOS)
    private let expandedVideoScale: CGFloat = 1.22
    #endif

    init(request: StreamPlaybackRequest, onBack: @escaping () -> Void) {
        self.request = request
        self.onBack = onBack
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            #if os(macOS)
            keyboardShortcuts
            #endif
            interactivePlayerSurface
            externalSubtitleOverlay
            nextEpisodeBanner
            playerChrome
            episodeSidebar
            episodeSidebarCloseButton
            startingOverlay
            errorOverlay
        }
        .background(Color.black)
        #if os(macOS)
        .onContinuousHover { phase in
            guard case .active = phase else { return }
            chromeVisibility.reveal()
            scheduleChromeHideIfNeeded()
        }
        #endif
        .onAppear {
            pendingResumePosition = progressStore.resumePosition(for: request)
            pendingTrackSelections = request.initialTrackSelections ?? progressStore.trackSelections(for: request)
            subtitleDelay = progressStore.subtitleDelay(for: request)
            progressStore.beginPlayback(for: request)
            startPlaybackIfPossible()
            refreshFullscreenState()
            scheduleChromeHideIfNeeded()
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            refreshFullscreenState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            refreshFullscreenState()
            completePendingBackAfterFullscreenExit()
        }
        #endif
        .task(id: request.id) {
            await loadExternalSubtitles()
        }
        .task(id: nextEpisode?.id) {
            await prefetchNextSource()
        }
        .onReceive(mpvController.$errorMessage) { errorMessage in
            guard errorMessage != nil else { return }
            chromeVisibility.keepVisible()
            startNativeFallbackIfPossible()
        }
        .onChange(of: isPaused) { _, isPaused in
            if isPaused {
                chromeVisibility.keepVisible()
            } else {
                scheduleChromeHideIfNeeded()
            }
        }
        .onChange(of: playbackErrorMessage) { _, errorMessage in
            if errorMessage == nil {
                scheduleChromeHideIfNeeded()
            } else {
                chromeVisibility.keepVisible()
                startNativeFallbackAfterRuntimeErrorIfPossible()
            }
        }
        .onChange(of: mpvController.didReachEnd) { _, didReachEnd in
            guard didReachEnd else { return }
            handlePlaybackEnded()
        }
        .onChange(of: playbackObserver.didFinishToEnd) { _, didFinishToEnd in
            guard didFinishToEnd else { return }
            handlePlaybackEnded()
        }
        #if os(iOS)
        .onChange(of: vlcController.didReachEnd) { _, didReachEnd in
            guard didReachEnd else { return }
            handlePlaybackEnded()
        }
        #endif
        .onChange(of: isEpisodeSidebarPresented) { _, isPresented in
            if isPresented {
                chromeVisibility.keepVisible()
            } else {
                scheduleChromeHideIfNeeded()
            }
        }
        .onChange(of: duration) { _, _ in
            applySavedProgressIfPossible()
            handlePlaybackEndIfNeeded()
        }
        .onChange(of: currentTime) { _, _ in
            handlePlaybackEndIfNeeded()
        }
        .onChange(of: audioTracks) { _, _ in
            applySavedTrackSelectionsIfPossible()
        }
        .onChange(of: subtitleTracks) { _, _ in
            applySavedTrackSelectionsIfPossible()
        }
        .onChange(of: nativeSubtitleTracks) { _, _ in
            ensureEmbeddedSubtitlesAreDisabled()
        }
        #if os(iOS)
        .onChange(of: vlcController.subtitleTracks) { _, _ in
            ensureEmbeddedSubtitlesAreDisabled()
        }
        #endif
        .onChange(of: externalSubtitleTracks) { _, _ in
            applySavedTrackSelectionsIfPossible()
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            saveCurrentProgress()
        }
        .onReceive(NotificationCenter.default.publisher(for: appWillTerminateNotification)) { _ in
            saveCurrentProgress(force: true)
        }
        .onDisappear {
            saveCurrentProgress(force: true)
            chromeVisibility.cancelAutoHide()
            cancelNativeStartupTimeout()
            player?.pause()
            removeNativeTimeObserver()
            playbackObserver.stop()
            #if os(iOS)
            vlcController.stop()
            #endif
            mpvController.stop()
        }
    }

    @ViewBuilder
    private var playerSurface: some View {
        #if os(macOS)
        if activePlaybackEngine == .mpv, let playbackURL = request.source.playbackURL {
            MPVPlayerView(
                url: playbackURL,
                externalSubtitles: externalSubtitleTracks,
                onEscape: handleEscape,
                controller: mpvController
            )
                .background(Color.black)
                .ignoresSafeArea()
        } else if activePlaybackEngine == .native, let player {
            NativePlayerView(player: player)
                .background(Color.black)
                .ignoresSafeArea()
        } else {
            Color.black.ignoresSafeArea()
        }
        #else
        if activePlaybackEngine == .vlc {
            VLCPlayerView(controller: vlcController)
                .background(Color.black)
                .iOSVideoZoom(scale: effectiveVideoScale)
                .ignoresSafeArea()
                .gesture(videoPinchGesture)
        } else if activePlaybackEngine == .native, let player {
            NativePlayerView(player: player)
                .background(Color.black)
                .iOSVideoZoom(scale: effectiveVideoScale)
                .ignoresSafeArea()
                .gesture(videoPinchGesture)
        } else {
            Color.black.ignoresSafeArea()
        }
        #endif
    }

    @ViewBuilder
    private var interactivePlayerSurface: some View {
        #if os(iOS)
        playerSurface
            .contentShape(Rectangle())
            .allowsHitTesting(!isChromePresented)
            .onTapGesture {
                guard !isAdjustingTimeline else { return }
                handlePlayerTap()
            }
        #else
        playerSurface
        #endif
    }

    private var playerChrome: some View {
        StreamPlayerChrome(
            title: request.title,
            subtitle: request.subtitle,
            isPaused: isPaused,
            isPreparingPlayback: isPreparingPlayback,
            currentTime: currentTime,
            duration: duration,
            volume: volume,
            isMuted: isMuted,
            isFullscreen: isFullscreen,
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks,
            subtitleDelay: subtitleDelay,
            canAdjustSubtitleDelay: selectedExternalSubtitleID != nil,
            canShowEpisodeSidebar: canShowEpisodeSidebar,
            isEpisodeSidebarPresented: isEpisodeSidebarPresented,
            onBack: handleBack,
            onPlayPause: togglePlayPause,
            onSeekBackward: {
                seek(by: -5)
            },
            onSeekForward: {
                seek(by: 5)
            },
            onSeek: seek(to:),
            onTimelineInteractionChange: handleTimelineInteractionChange,
            onVolumeChange: setVolume(_:),
            onMute: toggleMute,
            onAudioTrackSelect: selectAudioTrack(_:),
            onSubtitleTrackSelect: selectSubtitleTrack(_:),
            onSubtitleDelayChange: setSubtitleDelay(_:),
            onEpisodeSidebarOpen: showEpisodeSidebar,
            onFullscreen: toggleFullscreen,
            onBackgroundTap: handlePlayerTap
        )
        .opacity(isChromePresented ? 1 : 0)
        .allowsHitTesting(isChromePresented)
        .zIndex(3)
        .animation(.easeInOut(duration: 0.24), value: isChromePresented)
    }

    @ViewBuilder
    private var externalSubtitleOverlay: some View {
        #if os(iOS)
        if let subtitleText = currentExternalSubtitleText {
            VStack {
                Spacer(minLength: 0)

                Text(subtitleText)
                    .font(.system(size: 18, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.95), radius: 2, x: 0, y: 1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.horizontal, 28)
                    .padding(.bottom, isChromePresented ? 69 : 16)
            }
            .allowsHitTesting(false)
            .zIndex(2.5)
        }
        #endif
    }

    @ViewBuilder
    private var nextEpisodeBanner: some View {
        if shouldShowNextEpisodeBanner, let nextEpisode {
            VStack {
                Spacer(minLength: 0)

                HStack {
                    Spacer(minLength: 0)

                    StreamPlayerNextEpisodeBanner(
                        episodeTitle: nextEpisode.playbackTitle,
                        isLoading: isLoadingNextEpisode,
                        action: playNextEpisode
                    )
                    .padding(.trailing, 28)
                    .padding(.bottom, nextEpisodeBannerBottomPadding)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            .zIndex(4)
            .animation(.easeInOut(duration: 0.22), value: isChromePresented)
        }
    }

    @ViewBuilder
    private var episodeSidebar: some View {
        if isEpisodeSidebarPresented, let item = request.item {
            HStack(spacing: 0) {
                Spacer(minLength: 0)

                StreamPlayerEpisodeSidebar(
                    item: item,
                    currentEpisodeID: request.episode?.id,
                    currentSourceID: request.source.id,
                    currentTrackSelections: currentTrackSelections,
                    onClose: closeEpisodeSidebar
                )
            }
            .zIndex(4)
        }
    }

    @ViewBuilder
    private var episodeSidebarCloseButton: some View {
        #if os(iOS)
        if isEpisodeSidebarPresented {
            VStack {
                HStack {
                    Spacer(minLength: 0)

                    PlayerIconButton(
                        systemName: "xmark",
                        help: "Close episodes",
                        usesGlassBackground: true,
                        action: closeEpisodeSidebar
                    )
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)

                Spacer(minLength: 0)
            }
            .zIndex(5)
        }
        #endif
    }

    @ViewBuilder
    private var startingOverlay: some View {
        EmptyView()
    }

    @ViewBuilder
    private var errorOverlay: some View {
        if let errorMessage = playbackErrorMessage {
            DetailUnavailableView(
                systemImage: "exclamationmark.triangle",
                title: "Playback failed",
                message: errorMessage
            )
            .padding(24)
            .zIndex(2)
        }
    }

    private var keyboardShortcuts: some View {
        StreamPlayerKeyboardControls(
            onEscape: handleEscape,
            onBack: handleBack,
            onPlayPause: togglePlayPause,
            onFullscreen: toggleFullscreen,
            onEpisodeSidebarOpen: showEpisodeSidebar,
            onMute: toggleMute,
            onSeekBackward: {
                seek(by: -5)
            },
            onSeekForward: {
                seek(by: 5)
            }
        )
    }

    private var isPaused: Bool {
        #if os(iOS)
        if activePlaybackEngine == .vlc {
            return vlcController.isPaused
        }
        #endif
        return activePlaybackEngine == .mpv ? mpvController.isPaused : nativeIsPaused
    }

    private var currentTime: Double {
        #if os(iOS)
        if activePlaybackEngine == .vlc {
            return vlcController.currentTime
        }
        #endif
        return activePlaybackEngine == .mpv ? mpvController.currentTime : nativeTime
    }

    private var duration: Double {
        #if os(iOS)
        if activePlaybackEngine == .vlc {
            return vlcController.duration
        }
        #endif
        return activePlaybackEngine == .mpv ? mpvController.duration : nativeDuration
    }

    private var volume: Double {
        #if os(iOS)
        if activePlaybackEngine == .vlc {
            return vlcController.volume
        }
        #endif
        return activePlaybackEngine == .mpv ? mpvController.volume : nativeVolume
    }

    private var isMuted: Bool {
        #if os(iOS)
        if activePlaybackEngine == .vlc {
            return vlcController.isMuted
        }
        #endif
        return activePlaybackEngine == .mpv ? mpvController.isMuted : nativeIsMuted
    }

    private var audioTracks: [PlayerMediaTrack] {
        #if os(iOS)
        if activePlaybackEngine == .vlc {
            return vlcController.audioTracks
        }
        #endif
        return activePlaybackEngine == .mpv ? mpvController.audioTracks : nativeAudioTracks
    }

    private var subtitleTracks: [PlayerMediaTrack] {
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

    private var nativeSubtitleTracksWithExternalSubtitles: [PlayerMediaTrack] {
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
    private var vlcSubtitleTracksWithExternalSubtitles: [PlayerMediaTrack] {
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

    private var currentExternalSubtitleText: String? {
        guard selectedExternalSubtitleID != nil,
              activePlaybackEngine == .native || activePlaybackEngine == .vlc else {
            return nil
        }

        return ExternalSubtitleResolver.preferredText(
            in: externalSubtitleCues,
            at: currentTime - subtitleDelay
        )
    }

    private func setSubtitleDelay(_ delay: Double) {
        guard selectedExternalSubtitleID != nil else { return }
        subtitleDelay = min(max(delay, -10), 10)
        saveCurrentProgress(force: true)
        chromeVisibility.keepVisible()
    }

    private var playbackErrorMessage: String? {
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

    private var isPreparingPlayback: Bool {
        #if os(iOS)
        if activePlaybackEngine == .vlc {
            return vlcController.isStarting
        }
        #endif
        return isPreparingNativePlayback || (activePlaybackEngine == .mpv && mpvController.isStarting)
    }

    private var isChromePresented: Bool {
        chromeVisibility.isVisible || playbackErrorMessage != nil
    }

    private var shouldAutoHideChrome: Bool {
        !isPaused
            && playbackErrorMessage == nil
            && !isEpisodeSidebarPresented
            && !isAdjustingTimeline
    }

    #if os(iOS)
    private var effectiveVideoScale: CGFloat {
        videoScale
    }

    private var videoPinchGesture: some Gesture {
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

    private var currentTrackSelections: PlaybackTrackSelections {
        PlaybackTrackSelections(
            audio: selectedTrackChoice(from: audioTracks, kind: .audio),
            subtitle: selectedTrackChoice(from: subtitleTracks, kind: .subtitle)
        )
    }

    private var nextEpisode: CatalogEpisode? {
        guard request.contentType == .series,
              let item = request.item,
              let episode = request.episode else {
            return nil
        }

        return episodeWatchStore.nextEpisode(after: episode, in: item)
    }

    private var canShowEpisodeSidebar: Bool {
        request.contentType == .series && request.item != nil
    }

    private var shouldShowNextEpisodeBanner: Bool {
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

    private var nextEpisodeBannerBottomPadding: CGFloat {
        #if os(iOS)
        return isChromePresented ? 128 : 28
        #else
        return isChromePresented ? 92 : 28
        #endif
    }

    private var appWillTerminateNotification: Notification.Name {
        #if os(iOS)
        return UIApplication.willTerminateNotification
        #else
        return NSApplication.willTerminateNotification
        #endif
    }

    private func scheduleChromeHideIfNeeded() {
        chromeVisibility.scheduleAutoHide(isAllowed: shouldAutoHideChrome)
    }

    private func handleTimelineInteractionChange(_ isInteracting: Bool) {
        isAdjustingTimeline = isInteracting

        if isInteracting {
            chromeVisibility.keepVisible()
        } else {
            scheduleChromeHideIfNeeded()
        }
    }

    private func handlePlayerTap() {
        guard playbackErrorMessage == nil, !isEpisodeSidebarPresented, !isAdjustingTimeline else {
            chromeVisibility.keepVisible()
            return
        }

        if chromeVisibility.isVisible {
            chromeVisibility.hide()
        } else {
            chromeVisibility.reveal()
            if shouldAutoHideChrome {
                scheduleChromeHideIfNeeded()
            }
        }
    }

    private func performPlayerAction(_ action: () -> Void) {
        guard !isClosing else { return }
        chromeVisibility.reveal()
        action()
        scheduleChromeHideIfNeeded()
    }

    private func handleBack() {
        guard !isClosing else { return }
        if exitFullscreenIfNeeded() {
            shouldBackAfterFullscreenExit = true
            return
        }

        closePlayer()
    }

    private func handleEscape() {
        guard !isClosing else { return }
        if isEpisodeSidebarPresented {
            closeEpisodeSidebar()
            return
        }

        guard !exitFullscreenIfNeeded() else { return }

        closePlayer()
    }

    private func completePendingBackAfterFullscreenExit() {
        guard shouldBackAfterFullscreenExit else { return }
        shouldBackAfterFullscreenExit = false
        closePlayer()
    }

    private func closePlayer() {
        guard !isClosing else { return }
        isClosing = true
        saveCurrentProgress(force: true)
        if duration > 0, !canCompleteCurrentPlayback {
            clearCurrentPlaybackProgress()
        }
        chromeVisibility.cancelAutoHide()
        player?.pause()
        #if os(iOS)
        if activePlaybackEngine == .vlc {
            vlcController.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                onBack()
            }
            return
        }
        #endif
        mpvController.pause()
        onBack()
    }

    private func showEpisodeSidebar() {
        guard canShowEpisodeSidebar else { return }

        performPlayerAction {
            guard !isEpisodeSidebarPresented else { return }
            isEpisodeSidebarPresented = true
            chromeVisibility.keepVisible()
        }
    }

    private func closeEpisodeSidebar() {
        guard isEpisodeSidebarPresented else { return }

        performPlayerAction {
            isEpisodeSidebarPresented = false
        }
    }

    private func startPlaybackIfPossible() {
        guard player == nil, !isPreparingNativePlayback else { return }

        if let playbackURLError = request.source.playbackURLError {
            playbackObserver.errorMessage = playbackURLError
            return
        }

        guard let playbackURL = request.source.playbackURL else {
            playbackObserver.errorMessage = "This source does not expose a direct video URL. The native player can only open direct HTTP or HTTPS video streams returned by the addon."
            return
        }

        #if os(iOS)
        startVLCPlayback(with: playbackURL)
        #else
        guard request.source.preferredPlaybackEngine == .native else {
            activePlaybackEngine = .mpv
            playbackObserver.stop()
            playbackObserver.errorMessage = nil
            return
        }

        startNativePlayback(with: playbackURL)
        #endif
    }

    #if os(iOS)
    private func startVLCPlayback(with playbackURL: URL) {
        guard vlcController.isAvailable else {
            startNativePlayback(with: playbackURL)
            return
        }

        activePlaybackEngine = .vlc
        playbackObserver.stop()
        playbackObserver.errorMessage = nil
        vlcController.play(url: playbackURL)
    }
    #endif

    private func startNativeFallbackIfPossible() {
        #if os(macOS)
        guard activePlaybackEngine == .mpv,
              let playbackURL = request.source.playbackURL,
              player == nil else { return }

        mpvController.clearError()
        startNativePlayback(with: playbackURL)
        #endif
    }

    private func startNativePlayback(with playbackURL: URL) {
        isPreparingNativePlayback = true
        playbackObserver.errorMessage = nil

        Task {
            let result = await NativePlaybackCompatibilityResolver.validatedAsset(for: playbackURL)

            await MainActor.run {
                isPreparingNativePlayback = false
                guard !isClosing, player == nil else { return }

                if let asset = result.asset {
                    startNativePlayback(with: asset)
                } else {
                    handleNativeValidationFailure(
                        result.errorMessage ?? "iOS could not verify this stream before playback."
                    )
                }
            }
        }
    }

    private func handleNativeValidationFailure(_ message: String) {
        #if os(iOS)
        Task {
            guard let fallbackRequest = await fallbackPlaybackRequestAfterNativeFailure() else {
                await MainActor.run {
                    activePlaybackEngine = .native
                    playbackObserver.errorMessage = message
                    chromeVisibility.keepVisible()
                }
                return
            }

            await MainActor.run {
                StreamPlaybackStore.shared.request = fallbackRequest
            }
        }
        #else
        activePlaybackEngine = .native
        playbackObserver.errorMessage = message
        chromeVisibility.keepVisible()
        #endif
    }

    private func startNativeFallbackAfterRuntimeErrorIfPossible() {
        #if os(iOS)
        if vlcController.errorMessage?.contains("audio cannot be decoded") == true {
            return
        }

        guard !isPreparingNativePlayback,
              !isResolvingNativeFallback,
              activePlaybackEngine == .vlc || (activePlaybackEngine == .native && player != nil) else {
            return
        }

        isResolvingNativeFallback = true

        Task {
            let fallbackRequest = await fallbackPlaybackRequestAfterNativeFailure()

            await MainActor.run {
                isResolvingNativeFallback = false
                guard !isClosing, let fallbackRequest else { return }

                stopCurrentIOSPlaybackForFallback()
                StreamPlaybackStore.shared.request = fallbackRequest
            }
        }
        #endif
    }

    #if os(iOS)
    private func stopCurrentIOSPlaybackForFallback() {
        vlcController.stop()
        player?.pause()
        removeNativeTimeObserver()
        playbackObserver.stop()
        cancelNativeStartupTimeout()
        player = nil
    }
    #endif

    private func fallbackPlaybackRequestAfterNativeFailure() async -> StreamPlaybackRequest? {
        #if os(iOS)
        var attemptedSourceIDs = request.attemptedSourceIDs
        attemptedSourceIDs.insert(request.source.id)

        let sources = await StreamSourceResolver.fetchAllSources(
            from: addonStore.streamAddons,
            type: request.contentType,
            id: request.contentID
        )
        let candidates = sources.filter { source in
            !attemptedSourceIDs.contains(source.id)
                && NativePlaybackCompatibilityResolver.compatibility(for: source).canAttemptPlayback
        }

        guard let fallbackSource = NativePlaybackCompatibilityResolver.bestNativeSource(in: candidates) else {
            return nil
        }

        return StreamPlaybackRequest(
            source: fallbackSource,
            title: request.title,
            subtitle: request.subtitle,
            contentID: request.contentID,
            contentType: request.contentType,
            item: request.item,
            episode: request.episode,
            initialTrackSelections: request.initialTrackSelections,
            attemptedSourceIDs: attemptedSourceIDs
        )
        #else
        return nil
        #endif
    }

    private func startNativePlayback(with asset: AVURLAsset) {
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        activePlaybackEngine = .native
        self.player = player
        nativeIsPaused = false
        nativeVolume = Double(player.volume * 100)
        nativeIsMuted = player.isMuted
        playbackObserver.observe(playerItem: item)
        installNativeTimeObserver(player)
        refreshNativeMediaTracks()
        player.play()
        scheduleNativeStartupTimeout()
    }

    private func applySavedProgressIfPossible() {
        guard !hasAppliedSavedProgress,
              let pendingResumePosition,
              activePlaybackEngine != nil,
              duration > 0,
              pendingResumePosition < max(duration - 5, 0) else {
            return
        }

        hasAppliedSavedProgress = true
        seek(to: pendingResumePosition)
    }

    private func saveCurrentProgress(
        force: Bool = false,
        trackSelections: PlaybackTrackSelections? = nil
    ) {
        guard !hasCompletedCurrentContent,
              activePlaybackEngine != nil,
              playbackErrorMessage == nil,
              currentTime.isFinite,
              duration.isFinite else {
            return
        }

        if progressStore.isComplete(position: currentTime, duration: duration, contentType: request.contentType),
           canCompleteCurrentPlayback {
            completeCurrentContent()
            return
        }

        if duration > 0, !canCompleteCurrentPlayback {
            clearCurrentPlaybackProgress()
            return
        }

        if hasReachedPlaybackEnd && !canCompleteCurrentPlayback {
            return
        }

        if let pendingResumePosition,
           !hasAppliedSavedProgress,
           currentTime < pendingResumePosition {
            return
        }

        guard force || abs(currentTime - lastSavedProgressPosition) >= 1 else { return }

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

    private func completeCurrentContent() {
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

    private func handlePlaybackEnded() {
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

    private func handlePlaybackEndIfNeeded() {
        guard hasReachedPlaybackEnd else { return }
        handlePlaybackEnded()
    }

    private var hasReachedPlaybackEnd: Bool {
        guard currentTime.isFinite,
              duration.isFinite,
              duration > 0 else {
            return false
        }

        return max(duration - currentTime, 0) <= 1.25
    }

    private var canCompleteCurrentPlayback: Bool {
        guard duration.isFinite else { return false }

        switch request.contentType {
        case .movie:
            return duration >= minimumCompletableMovieDuration
        case .series:
            return duration >= minimumCompletableEpisodeDuration
        }
    }

    private func clearCurrentPlaybackProgress() {
        progressStore.clearProgress(contentID: request.contentID, contentType: request.contentType)
    }

    private func savePendingNextEpisodeProgress(
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
            subtitle: item.title,
            trackSelections: trackSelections,
            subtitleDelay: subtitleDelay
        )

        guard prefetchedSource(for: episode) == nil else { return }

        Task {
            guard let refreshedSource = await firstSource(for: episode) else { return }
            await MainActor.run {
                progressStore.savePendingProgress(
                    for: item,
                    episode: episode,
                    source: refreshedSource,
                    subtitle: item.title,
                    trackSelections: trackSelections,
                    subtitleDelay: subtitleDelay
                )
            }
        }
    }

    private func loadExternalSubtitles() async {
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

    private func togglePlayPause() {
        performPlayerAction {
            switch activePlaybackEngine {
            case .mpv:
                mpvController.togglePlayPause()
            case .vlc:
                #if os(iOS)
                vlcController.togglePlayPause()
                #endif
            case .native:
                guard let player else { return }
                if player.timeControlStatus == .playing {
                    player.pause()
                    nativeIsPaused = true
                } else {
                    player.play()
                    nativeIsPaused = false
                }
            case nil:
                break
            }
        }
    }

    private func seek(to time: Double) {
        performPlayerAction {
            switch activePlaybackEngine {
            case .mpv:
                mpvController.seek(to: time)
            case .vlc:
                #if os(iOS)
                vlcController.seek(to: time)
                #endif
            case .native:
                let target = CMTime(seconds: time, preferredTimescale: 600)
                player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                nativeTime = time
            case nil:
                break
            }
        }
    }

    private func seek(by offset: Double) {
        performPlayerAction {
            switch activePlaybackEngine {
            case .mpv:
                mpvController.seek(by: offset)
            case .vlc:
                #if os(iOS)
                vlcController.seek(by: offset)
                #endif
            case .native:
                let targetTime = min(max(nativeTime + offset, 0), max(nativeDuration, 0))
                seek(to: targetTime)
            case nil:
                break
            }
        }
    }

    private func setVolume(_ value: Double) {
        performPlayerAction {
            let clampedValue = min(max(value, 0), 100)

            switch activePlaybackEngine {
            case .mpv:
                mpvController.setVolume(clampedValue)
            case .vlc:
                #if os(iOS)
                vlcController.setVolume(clampedValue)
                #endif
            case .native:
                player?.volume = Float(clampedValue / 100)
                player?.isMuted = clampedValue == 0
                nativeVolume = clampedValue
                nativeIsMuted = player?.isMuted ?? nativeIsMuted
            case nil:
                break
            }
        }
    }

    private func toggleMute() {
        performPlayerAction {
            switch activePlaybackEngine {
            case .mpv:
                mpvController.toggleMute()
            case .vlc:
                #if os(iOS)
                vlcController.toggleMute()
                #endif
            case .native:
                guard let player else { return }
                player.isMuted.toggle()
                nativeIsMuted = player.isMuted
            case nil:
                break
            }
        }
    }

    private func playNextEpisode() {
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
                source = await firstSource(for: nextEpisode)
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
                    initialTrackSelections: trackSelections
                )
            }
        }
    }

    private func prefetchNextSource() async {
        guard let nextEpisode else {
            prefetchedNextEpisodeID = nil
            prefetchedNextSource = nil
            return
        }

        prefetchedNextEpisodeID = nextEpisode.id
        prefetchedNextSource = nil
        let source = await firstSource(for: nextEpisode)
        guard prefetchedNextEpisodeID == nextEpisode.id else { return }
        prefetchedNextSource = source
    }

    private func prefetchedSource(for episode: CatalogEpisode) -> StreamSource? {
        guard prefetchedNextEpisodeID == episode.id else { return nil }
        return prefetchedNextSource
    }

    private func firstSource(for episode: CatalogEpisode) async -> StreamSource? {
        await StreamSourceResolver.firstSource(
            from: addonStore.streamAddons,
            type: .series,
            id: episode.id
        )
    }

    private func selectAudioTrack(_ track: PlayerMediaTrack) {
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

    private func selectSubtitleTrack(_ track: PlayerMediaTrack) {
        performPlayerAction {
            switch activePlaybackEngine {
            case .mpv:
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

    private func selectNativeSubtitleTrack(_ track: PlayerMediaTrack) {
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
    private func selectVLCSubtitleTrack(_ track: PlayerMediaTrack) {
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

    private func loadExternalSubtitleCues(for subtitle: ExternalSubtitleTrack) {
        loadingExternalSubtitleID = subtitle.id
        externalSubtitleCues = []

        Task {
            let cues = (try? await ExternalSubtitleResolver.loadCues(from: subtitle)) ?? []

            await MainActor.run {
                guard loadingExternalSubtitleID == subtitle.id else { return }
                externalSubtitleCues = cues
                loadingExternalSubtitleID = nil
            }
        }
    }

    private func clearExternalSubtitleSelection() {
        selectedExternalSubtitleID = nil
        loadingExternalSubtitleID = nil
        externalSubtitleCues = []
    }

    private func ensureEmbeddedSubtitlesAreDisabled() {
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

    private func toggleFullscreen() {
        #if os(macOS)
        performPlayerAction {
            NSApp.keyWindow?.toggleFullScreen(nil)
        }
        #else
        performPlayerAction {
            isFullscreen.toggle()
        }
        #endif
    }

    private func exitFullscreenIfNeeded() -> Bool {
        #if os(macOS)
        guard let window = NSApp.keyWindow,
              window.styleMask.contains(.fullScreen) else { return false }

        chromeVisibility.reveal()
        window.toggleFullScreen(nil)
        return true
        #else
        return false
        #endif
    }

    private func refreshFullscreenState() {
        #if os(macOS)
        isFullscreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) == true
        #else
        isFullscreen = true
        #endif
    }

    private func installNativeTimeObserver(_ player: AVPlayer) {
        removeNativeTimeObserver()
        nativeTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.4, preferredTimescale: 600),
            queue: .main
        ) { [weak player] time in
            Task { @MainActor in
                nativeTime = time.seconds.isFinite ? time.seconds : 0
                let duration = player?.currentItem?.duration.seconds ?? 0
                nativeDuration = duration.isFinite ? duration : 0
                nativeIsPaused = player?.timeControlStatus != .playing
                nativeVolume = Double((player?.volume ?? 1) * 100)
                nativeIsMuted = player?.isMuted ?? false
                if nativeTime > nativeStartupMinimumProgress {
                    cancelNativeStartupTimeout()
                }
                refreshNativeMediaTracks()
            }
        }
    }

    private func removeNativeTimeObserver() {
        if let nativeTimeObserver {
            player?.removeTimeObserver(nativeTimeObserver)
            self.nativeTimeObserver = nil
        }
    }

    private func scheduleNativeStartupTimeout() {
        #if os(iOS)
        cancelNativeStartupTimeout()
        let timeoutWorkItem = DispatchWorkItem {
            handleNativeStartupTimeoutIfNeeded()
        }
        nativeStartupTimeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeoutWorkItem)
        #endif
    }

    private func cancelNativeStartupTimeout() {
        nativeStartupTimeoutWorkItem?.cancel()
        nativeStartupTimeoutWorkItem = nil
    }

    private func handleNativeStartupTimeoutIfNeeded() {
        #if os(iOS)
        guard activePlaybackEngine == .native,
              player != nil,
              nativeTime <= nativeStartupMinimumProgress,
              !isResolvingNativeFallback else {
            return
        }

        isResolvingNativeFallback = true

        Task {
            let fallbackRequest = await fallbackPlaybackRequestAfterNativeFailure()

            await MainActor.run {
                isResolvingNativeFallback = false

                player?.pause()
                removeNativeTimeObserver()
                playbackObserver.stop()
                cancelNativeStartupTimeout()

                if let fallbackRequest {
                    player = nil
                    StreamPlaybackStore.shared.request = fallbackRequest
                } else {
                    activePlaybackEngine = .native
                    playbackObserver.errorMessage = "This stream did not start in time. It may use codecs, headers, or a server response that AVPlayer on iOS cannot handle reliably."
                    chromeVisibility.keepVisible()
                }
            }
        }
        #endif
    }

    private func refreshNativeMediaTracks() {
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

    private func selectNativeTrack(_ track: PlayerMediaTrack, characteristic: AVMediaCharacteristic) {
        NativePlayerTrackResolver.select(track, in: player?.currentItem, for: characteristic)
        refreshNativeMediaTracks()
    }

    private func applySavedTrackSelectionsIfPossible() {
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

    private func selectStoredTrack(_ track: PlayerMediaTrack) {
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

    private func matchingTrack(for choice: PlaybackTrackChoice, in tracks: [PlayerMediaTrack]) -> PlayerMediaTrack? {
        tracks.first { $0.id == choice.id }
            ?? tracks.first {
                $0.isOff == choice.isOff
                    && $0.language == choice.language
                    && $0.title == choice.title
            }
    }

    private func externalSubtitleTrackID(for subtitle: ExternalSubtitleTrack) -> String {
        "external-subtitle-\(subtitle.id)"
    }

    private func selectedTrackChoice(from tracks: [PlayerMediaTrack], kind: PlayerMediaTrack.Kind) -> PlaybackTrackChoice? {
        guard let track = tracks.first(where: { $0.kind == kind && $0.isSelected }) else { return nil }

        return trackChoice(from: track)
    }

    private func trackChoice(from track: PlayerMediaTrack) -> PlaybackTrackChoice {
        return PlaybackTrackChoice(
            id: track.id,
            title: track.title,
            language: track.language,
            isOff: track.isOff
        )
    }
}

#if os(iOS)
private extension View {
    func iOSVideoZoom(scale: CGFloat) -> some View {
        self
            .scaleEffect(scale)
            .clipped()
    }
}
#endif
