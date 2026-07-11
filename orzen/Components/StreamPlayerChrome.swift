import SwiftUI

struct StreamPlayerChrome: View {
    let title: String
    let subtitle: String
    let isPaused: Bool
    let isPreparingPlayback: Bool
    let currentTime: Double
    let duration: Double
    let volume: Double
    let isMuted: Bool
    let isFullscreen: Bool
    let audioTracks: [PlayerMediaTrack]
    let subtitleTracks: [PlayerMediaTrack]
    let canShowEpisodeSidebar: Bool
    let isEpisodeSidebarPresented: Bool
    let onBack: () -> Void
    let onPlayPause: () -> Void
    let onSeekBackward: () -> Void
    let onSeekForward: () -> Void
    let onSeek: (Double) -> Void
    let onTimelineInteractionChange: (Bool) -> Void
    let onVolumeChange: (Double) -> Void
    let onMute: () -> Void
    let onAudioTrackSelect: (PlayerMediaTrack) -> Void
    let onSubtitleTrackSelect: (PlayerMediaTrack) -> Void
    let onEpisodeSidebarOpen: () -> Void
    let onFullscreen: () -> Void
    let onBackgroundTap: () -> Void
    @State private var timelinePreviewTime: Double?

    var body: some View {
        ZStack {
            #if os(iOS)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onBackgroundTap)
            #endif

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                controls
            }

            centerPlayButton
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 22)
        .padding(.bottom, bottomPadding)
        .background {
            chromeGradient
                .ignoresSafeArea()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .ignoresSafeArea(.container, edges: .bottom)
        #endif
    }

    private var header: some View {
        HStack(spacing: 14) {
            backButton

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            #if os(iOS)
            PlayerIconButton(
                systemName: "list.bullet",
                help: canShowEpisodeSidebar ? "Episodes" : "Episodes are available for series",
                isEnabled: canShowEpisodeSidebar,
                usesGlassBackground: true,
                action: onEpisodeSidebarOpen
            )
            #endif
        }
    }

    @ViewBuilder
    private var backButton: some View {
        circularButton(help: "Back", action: onBack) {
            backIcon
        }
    }

    private var backIcon: some View {
        Image(systemName: "chevron.left")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white.opacity(0.92))
            .frame(width: 44, height: 44)
    }

    @ViewBuilder
    private var centerPlayButton: some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 34) {
                centerTransportButtons
            }
        } else {
            centerTransportButtons
        }
        #else
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 34) {
                centerTransportButtons
            }
        } else {
            centerTransportButtons
        }
        #endif
    }

    private var centerTransportButtons: some View {
        HStack(spacing: 34) {
            centerTransportButton(
                systemName: "5.arrow.trianglehead.counterclockwise",
                size: .small,
                help: "Rewind 5 seconds",
                action: onSeekBackward
            )

            centerTransportButton(
                systemName: isPaused ? "play.fill" : "pause.fill",
                size: .large,
                help: isPreparingPlayback ? "Loading" : (isPaused ? "Play" : "Pause"),
                isLoading: isPreparingPlayback,
                isEnabled: !isPreparingPlayback,
                action: onPlayPause
            )

            centerTransportButton(
                systemName: "5.arrow.trianglehead.clockwise",
                size: .small,
                help: "Forward 5 seconds",
                action: onSeekForward
            )
        }
    }

    private var controls: some View {
        #if os(iOS)
        mobileControls
        #else
        desktopControls
        #endif
    }

    private var desktopControls: some View {
        VStack(spacing: 12) {
            PlayerFlatSlider(
                value: Binding(
                    get: { displayedTimelineTime },
                    set: { timelinePreviewTime = $0 }
                ),
                in: 0...max(duration, 1),
                accessibilityLabel: "Playback position",
                expandsWhileInteracting: true,
                onInteractionChange: handleTimelineInteraction
            )
            .offset(y: 12)

            HStack(spacing: 12) {
                PlayerIconButton(
                    systemName: isPaused ? "play.fill" : "pause.fill",
                    help: isPaused ? "Play" : "Pause",
                    action: onPlayPause
                )

                PlayerIconButton(
                    systemName: isMuted || volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    help: isMuted ? "Unmute" : "Mute",
                    action: onMute
                )

                PlayerFlatSlider(
                    value: Binding(
                        get: { displayedVolume },
                        set: { onVolumeChange($0) }
                    ),
                    in: 0...100,
                    accessibilityLabel: "Volume"
                )
                .frame(width: 92)

                Text("\(formatTime(displayedTimelineTime)) / \(formatTime(duration))")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundColor(.white.opacity(0.86))
                    .frame(minWidth: 96, alignment: .leading)

                Spacer(minLength: 0)

                PlayerTrackMenu(
                    systemName: "captions.bubble",
                    help: "Subtitles",
                    emptyTitle: "No subtitles",
                    tracks: subtitleTracks,
                    onSelect: onSubtitleTrackSelect
                )
                .equatable()

                PlayerTrackMenu(
                    systemName: "waveform",
                    help: "Audio",
                    emptyTitle: "No audio tracks",
                    tracks: audioTracks,
                    onSelect: onAudioTrackSelect
                )
                .equatable()

                PlayerIconButton(
                    systemName: "sidebar.right",
                    help: canShowEpisodeSidebar ? "Episodes" : "Episodes are available for series",
                    isEnabled: canShowEpisodeSidebar,
                    action: onEpisodeSidebarOpen
                )

                PlayerIconButton(
                    systemName: fullscreenIconName,
                    help: "Fullscreen",
                    action: onFullscreen
                )
            }
        }
    }

    private var mobileControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)

                mobileTrackOptions
            }

            PlayerFlatSlider(
                value: Binding(
                    get: { displayedTimelineTime },
                    set: { timelinePreviewTime = $0 }
                ),
                in: 0...max(duration, 1),
                accessibilityLabel: "Playback position",
                expandsWhileInteracting: true,
                onInteractionChange: handleTimelineInteraction
            )

            HStack {
                Text(formatTime(displayedTimelineTime))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundColor(.white.opacity(0.86))

                Spacer(minLength: 0)

                Text(formatTime(duration))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundColor(.white.opacity(0.58))
            }
        }
    }

    @ViewBuilder
    private var mobileTrackOptions: some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 10) {
                mobileTrackButtons
            }
            .glassEffect(interactiveGlass, in: Capsule())
        } else {
            mobileTrackButtons
                .padding(.horizontal, 4)
                .background(.black.opacity(0.28), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
        }
        #else
        mobileTrackButtons
        #endif
    }

    private var mobileTrackButtons: some View {
        HStack(spacing: 10) {
            PlayerTrackMenu(
                systemName: "captions.bubble",
                help: "Subtitles",
                emptyTitle: "No subtitles",
                tracks: subtitleTracks,
                size: 46,
                onSelect: onSubtitleTrackSelect
            )

            PlayerTrackMenu(
                systemName: "waveform",
                help: "Audio",
                emptyTitle: "No audio tracks",
                tracks: audioTracks,
                size: 46,
                onSelect: onAudioTrackSelect
            )
        }
    }

    private var chromeGradient: some View {
        ZStack {
            Color.black.opacity(0.18)

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.86), .black.opacity(0.48), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 180)

                Spacer()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.62), .black.opacity(0.92)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)
            }
        }
        .allowsHitTesting(false)
    }

    private var fullscreenIconName: String {
        isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
    }

    @available(iOS 26, macOS 26, *)
    private var interactiveGlass: Glass {
        .clear.interactive()
    }

    private var horizontalPadding: CGFloat {
        #if os(iOS)
        return 18
        #else
        return 24
        #endif
    }

    private var bottomPadding: CGFloat {
        #if os(iOS)
        return 8
        #else
        return 18
        #endif
    }

    private var displayedVolume: Double {
        isMuted ? 0 : volume
    }

    private var displayedTimelineTime: Double {
        let playbackTime = min(currentTime, max(duration, 0))
        return timelinePreviewTime ?? playbackTime
    }

    private func handleTimelineInteraction(_ isInteracting: Bool) {
        onTimelineInteractionChange(isInteracting)

        if isInteracting {
            timelinePreviewTime = displayedTimelineTime
            return
        }

        guard let timelinePreviewTime else { return }
        onSeek(timelinePreviewTime)
        self.timelinePreviewTime = nil
    }

    private func centerTransportButton(
        systemName: String,
        size: CenterTransportButtonSize,
        help: String,
        isLoading: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        return circularButton(
            help: help,
            isEnabled: isEnabled,
            action: action
        ) {
            centerTransportIcon(systemName: systemName, size: size, isLoading: isLoading)
        }
    }

    @ViewBuilder
    private func circularButton<Icon: View>(
        help: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button(action: action) {
            icon()
                .modifier(PlayerLiquidGlassCircleSurface(isActive: true))
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .help(help)
        .accessibilityLabel(help)
        .disabled(!isEnabled)
    }

    @ViewBuilder
    private func centerTransportIcon(
        systemName: String,
        size: CenterTransportButtonSize,
        isLoading: Bool = false
    ) -> some View {
        if isLoading {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
                .frame(width: size.buttonSize, height: size.buttonSize)
        } else {
            Image(systemName: systemName)
                .font(.system(size: size.iconSize, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: size.buttonSize, height: size.buttonSize)
        }
    }

    private func formatTime(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0:00" }

        let totalSeconds = Int(value.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }
}

private enum CenterTransportButtonSize {
    case small
    case large

    var buttonSize: CGFloat {
        switch self {
        case .small:
            54
        case .large:
            76
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .small:
            23
        case .large:
            34
        }
    }
}
