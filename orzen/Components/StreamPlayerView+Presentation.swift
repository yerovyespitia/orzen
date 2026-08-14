import SwiftUI
#if os(iOS)
import UIKit
#endif

extension StreamPlayerView {
    @ViewBuilder
    var playerSurface: some View {
        #if os(macOS)
        if activePlaybackEngine == .mpv, let playbackURL = request.source.playbackURL {
            MPVPlayerView(
                url: playbackURL,
                externalSubtitles: externalSubtitleTracks,
                seekInterval: seekInterval,
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
            VLCPlayerView(
                controller: vlcController,
                pictureInPictureSession: pictureInPictureSession,
                pictureInPictureSubtitleText: currentExternalSubtitleText
            )
                .background(Color.black)
                .iOSVideoZoom(scale: effectiveVideoScale)
                .ignoresSafeArea()
                .gesture(videoPinchGesture)
        } else if activePlaybackEngine == .native, let player {
            NativePlayerView(
                player: player,
                pictureInPictureSession: pictureInPictureSession
            )
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
    var interactivePlayerSurface: some View {
        #if os(iOS)
        playerSurface
            .overlay {
                GeometryReader { proxy in
                    Color.clear
                        .contentShape(Rectangle())
                        .allowsHitTesting(!isChromePresented)
                        .onTapGesture {
                            guard !isAdjustingTimeline else { return }
                            handlePlayerTap()
                        }
                        .highPriorityGesture(
                            SpatialTapGesture(count: 2, coordinateSpace: .local)
                                .onEnded { value in
                                    handlePlayerDoubleTap(
                                        at: value.location,
                                        in: proxy.size.width
                                    )
                                }
                        )
                }
            }
        #else
        playerSurface
        #endif
    }

    var playerChrome: some View {
        StreamPlayerChrome(
            title: request.title,
            subtitle: request.contentType == .series ? request.subtitle : nil,
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
            isPictureInPictureAvailable: isPictureInPictureAvailable,
            isPictureInPictureActive: isPictureInPictureActive,
            seekInterval: seekInterval,
            onBack: handleBack,
            onPlayPause: togglePlayPause,
            onSeekBackward: {
                seek(by: -seekInterval.seconds)
            },
            onSeekForward: {
                seek(by: seekInterval.seconds)
            },
            onSeek: seek(to:),
            onTimelineInteractionChange: handleTimelineInteractionChange,
            onVolumeChange: setVolume(_:),
            onMute: toggleMute,
            onAudioTrackSelect: selectAudioTrack(_:),
            onSubtitleTrackSelect: selectSubtitleTrack(_:),
            onSubtitleDelayChange: setSubtitleDelay(_:),
            onEpisodeSidebarOpen: showEpisodeSidebar,
            onPictureInPicture: togglePictureInPicture,
            onFullscreen: toggleFullscreen,
            onBackgroundTap: handlePlayerTap,
            onDoubleTapSeek: { location, width in
                #if os(iOS)
                handlePlayerDoubleTap(at: location, in: width)
                #endif
            }
        )
        .opacity(isChromePresented ? 1 : 0)
        .allowsHitTesting(isChromePresented)
        .zIndex(3)
        .animation(.easeInOut(duration: 0.24), value: isChromePresented)
    }

    @ViewBuilder
    var doubleTapSeekFeedbackOverlay: some View {
        #if os(iOS)
        if let seekOffset = doubleTapSeekFeedback {
            GeometryReader { proxy in
                Text(doubleTapSeekFeedbackText(for: seekOffset))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.46), in: Capsule())
                    .position(
                        x: seekOffset < 0 ? proxy.size.width * 0.25 : proxy.size.width * 0.75,
                        y: proxy.size.height * 0.5
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            .allowsHitTesting(false)
            .zIndex(3.5)
            .task(id: doubleTapSeekFeedbackID) {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }

                withAnimation(.easeOut(duration: 0.35)) {
                    doubleTapSeekFeedback = nil
                }
            }
        }
        #endif
    }

    @ViewBuilder
    var externalSubtitleOverlay: some View {
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
                    .padding(.bottom, isChromePresented ? 64 : 16)
            }
            .allowsHitTesting(false)
            .zIndex(2.5)
        }
        #endif
    }

    @ViewBuilder
    var nextEpisodeBanner: some View {
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
    var episodeSidebar: some View {
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
    var startingOverlay: some View {
        EmptyView()
    }

    @ViewBuilder
    var errorOverlay: some View {
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

    var keyboardShortcuts: some View {
        StreamPlayerKeyboardControls(
            onEscape: handleEscape,
            onBack: handleBack,
            onPlayPause: togglePlayPause,
            onFullscreen: toggleFullscreen,
            onEpisodeSidebarOpen: showEpisodeSidebar,
            onMute: toggleMute,
            onSeekBackward: {
                seek(by: -seekInterval.seconds)
            },
            onSeekForward: {
                seek(by: seekInterval.seconds)
            }
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
