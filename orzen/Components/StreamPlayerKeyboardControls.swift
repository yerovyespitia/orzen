import SwiftUI

struct StreamPlayerKeyboardControls: View {
    let onEscape: () -> Void
    let onBack: () -> Void
    let onPlayPause: () -> Void
    let onFullscreen: () -> Void
    let onEpisodeSidebarOpen: () -> Void
    let onMute: () -> Void
    let onSeekBackward: () -> Void
    let onSeekForward: () -> Void

    var body: some View {
        PlaybackKeyboardShortcutView(
            onEscape: onEscape,
            onSpace: onPlayPause,
            onFullscreen: onFullscreen,
            onMute: onMute,
            onSeekBackward: onSeekBackward,
            onSeekForward: onSeekForward
        )
        .allowsHitTesting(false)
        .overlay(alignment: .bottomLeading) {
            hiddenKeyboardButtons
        }
    }

    private var hiddenKeyboardButtons: some View {
        HStack(spacing: 14) {
            Button(action: onEscape) {
                EmptyView()
            }
            .keyboardShortcut(.cancelAction)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: onPlayPause) {
                EmptyView()
            }
            .keyboardShortcut(.space, modifiers: [])
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: onFullscreen) {
                EmptyView()
            }
            .keyboardShortcut("f", modifiers: [])
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: onEpisodeSidebarOpen) {
                EmptyView()
            }
            .keyboardShortcut("s", modifiers: [])
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .accessibilityHidden(true)
    }
}
