import AVKit
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct StreamPlayerView: View {
    let request: StreamPlaybackRequest
    let onBack: () -> Void

    @ObservedObject var addonStore = LocalAddonStore.shared
    @ObservedObject var subtitlePreferences = SubtitlePreferencesStore.shared
    @ObservedObject var progressStore = PlaybackProgressStore.shared
    @ObservedObject var collectionStore = CollectionStore.shared
    @ObservedObject var episodeWatchStore = EpisodeWatchStore.shared
    @State var player: AVPlayer?
    @State var nativeTime: Double = 0
    @State var nativeDuration: Double = 0
    @State var nativeIsPaused = false
    @State var nativeVolume: Double = 100
    @State var nativeIsMuted = false
    @State var nativeAudioTracks: [PlayerMediaTrack] = []
    @State var nativeSubtitleTracks: [PlayerMediaTrack] = []
    @State var externalSubtitleTracks: [ExternalSubtitleTrack] = []
    @State var selectedExternalSubtitleID: String?
    @State var externalSubtitleCues: [ExternalSubtitleCue] = []
    @State var loadingExternalSubtitleID: String?
    @State var subtitleDelay: Double = 0
    @State var nativeTimeObserver: Any?
    @State var isPreparingNativePlayback = false
    @State var isResolvingNativeFallback = false
    @State var nativeStartupTimeoutWorkItem: DispatchWorkItem?
    @State var isFullscreen = false
    @State var isClosing = false
    @State var shouldBackAfterFullscreenExit = false
    @State var activePlaybackEngine: StreamPlaybackEngine?
    @State var pendingResumePosition: Double?
    @State var pendingTrackSelections: PlaybackTrackSelections?
    @State var hasAppliedSavedProgress = false
    @State var appliedSavedAudioTrackID: String?
    @State var appliedSavedSubtitleTrackID: String?
    @State var lastSavedProgressPosition: Double = 0
    @State var hasCompletedCurrentContent = false
    @State var hasHandledPlaybackEnd = false
    @State var isLoadingNextEpisode = false
    @State var isEpisodeSidebarPresented = false
    @State var isAdjustingTimeline = false
    @State var prefetchedNextEpisodeID: CatalogEpisode.ID?
    @State var prefetchedNextSource: StreamSource?
    @StateObject var playbackObserver = StreamPlaybackObserver()
    #if os(iOS)
    @StateObject var vlcController = VLCPlaybackController()
    #endif
    @StateObject var mpvController = MPVPlaybackController()
    @StateObject var chromeVisibility = StreamPlayerChromeVisibilityController()
    #if os(iOS)
    @State var videoScale: CGFloat = 1
    #endif

    let nativeStartupMinimumProgress = 1.0
    #if os(iOS)
    let expandedVideoScale: CGFloat = 1.22
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
            saveProgressOnDisappearIfNeeded()
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
}
