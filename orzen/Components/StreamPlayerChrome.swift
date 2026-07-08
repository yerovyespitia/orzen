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
    let canPlayNextEpisode: Bool
    let canShowEpisodeSidebar: Bool
    let isEpisodeSidebarPresented: Bool
    let onBack: () -> Void
    let onPlayPause: () -> Void
    let onSeekBackward: () -> Void
    let onSeekForward: () -> Void
    let onSeek: (Double) -> Void
    let onVolumeChange: (Double) -> Void
    let onMute: () -> Void
    let onNextEpisode: () -> Void
    let onAudioTrackSelect: (PlayerMediaTrack) -> Void
    let onSubtitleTrackSelect: (PlayerMediaTrack) -> Void
    let onEpisodeSidebarToggle: () -> Void
    let onFullscreen: () -> Void
    @State private var hoveredCircularButton: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 0)
            centerPlayButton
            Spacer(minLength: 0)
            controls
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
        }
    }

    @ViewBuilder
    private var backButton: some View {
        let hoverID = "player-back"
        circularButton(hoverID: hoverID, help: "Back", action: onBack) {
            backIcon
        }
    }

    private var backIcon: some View {
        Image(systemName: "chevron.left")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white.opacity(0.92))
            .frame(width: 34, height: 34)
    }

    @ViewBuilder
    private var centerPlayButton: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 34) {
                centerTransportButtons
            }
        } else {
            centerTransportButtons
        }
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
                    get: { min(currentTime, max(duration, 0)) },
                    set: { onSeek($0) }
                ),
                in: 0...max(duration, 1),
                accessibilityLabel: "Playback position"
            )

            HStack(spacing: 12) {
                PlayerIconButton(
                    systemName: isPaused ? "play.fill" : "pause.fill",
                    help: isPaused ? "Play" : "Pause",
                    action: onPlayPause
                )

                if canPlayNextEpisode {
                    PlayerIconButton(
                        systemName: "forward.end.fill",
                        help: "Next episode",
                        action: onNextEpisode
                    )
                }

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

                Text("\(formatTime(currentTime)) / \(formatTime(duration))")
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
                    action: onEpisodeSidebarToggle
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
        VStack(spacing: 14) {
            PlayerFlatSlider(
                value: Binding(
                    get: { min(currentTime, max(duration, 0)) },
                    set: { onSeek($0) }
                ),
                in: 0...max(duration, 1),
                accessibilityLabel: "Playback position"
            )

            HStack(spacing: 14) {
                Text(formatTime(currentTime))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundColor(.white.opacity(0.86))

                Spacer(minLength: 0)

                if canPlayNextEpisode {
                    PlayerIconButton(
                        systemName: "forward.end.fill",
                        help: "Next episode",
                        action: onNextEpisode
                    )
                }

                PlayerTrackMenu(
                    systemName: "captions.bubble",
                    help: "Subtitles",
                    emptyTitle: "No subtitles",
                    tracks: subtitleTracks,
                    onSelect: onSubtitleTrackSelect
                )

                PlayerTrackMenu(
                    systemName: "waveform",
                    help: "Audio",
                    emptyTitle: "No audio tracks",
                    tracks: audioTracks,
                    onSelect: onAudioTrackSelect
                )

                PlayerIconButton(
                    systemName: "sidebar.right",
                    help: canShowEpisodeSidebar ? "Episodes" : "Episodes are available for series",
                    isEnabled: canShowEpisodeSidebar,
                    action: onEpisodeSidebarToggle
                )

                Text(formatTime(duration))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundColor(.white.opacity(0.58))
            }
        }
    }

    private var chromeGradient: some View {
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
        .allowsHitTesting(false)
    }

    private var fullscreenIconName: String {
        isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
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

    private func centerTransportButton(
        systemName: String,
        size: CenterTransportButtonSize,
        help: String,
        isLoading: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        let hoverID = "transport-\(systemName)-\(size.buttonSize)"

        return circularButton(hoverID: hoverID, help: help, isEnabled: isEnabled, action: action) {
            centerTransportIcon(systemName: systemName, size: size, isLoading: isLoading)
        }
    }

    @ViewBuilder
    private func circularButton<Icon: View>(
        hoverID: String,
        help: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        if #available(macOS 26, *) {
            Button(action: action) {
                icon()
                    .background(circularButtonBackground(hoverID: hoverID))
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            #if os(macOS)
            .onHover { hovering in
                hoveredCircularButton = hovering ? hoverID : nil
            }
            #endif
            .animation(.easeInOut(duration: 0.12), value: hoveredCircularButton)
            .help(help)
            .accessibilityLabel(help)
            .disabled(!isEnabled)
        } else {
            Button(action: action) {
                icon()
                    .background(circularButtonBackground(hoverID: hoverID))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            #if os(macOS)
            .onHover { hovering in
                hoveredCircularButton = hovering ? hoverID : nil
            }
            #endif
            .animation(.easeInOut(duration: 0.12), value: hoveredCircularButton)
            .help(help)
            .accessibilityLabel(help)
            .disabled(!isEnabled)
        }
    }

    private func circularButtonBackground(hoverID: String) -> some View {
        let isHovered = hoveredCircularButton == hoverID

        return Circle()
            .fill(Color.white.opacity(isHovered ? 0.16 : 0.08))
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(isHovered ? 0.14 : 0.06), lineWidth: 1)
            )
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
