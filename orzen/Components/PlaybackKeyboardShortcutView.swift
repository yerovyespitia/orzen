import SwiftUI

#if os(macOS)
struct PlaybackKeyboardShortcutView: NSViewRepresentable {
    let onEscape: () -> Void
    let onSpace: () -> Void
    let onFullscreen: () -> Void
    let onMute: () -> Void
    let onSeekBackward: () -> Void
    let onSeekForward: () -> Void

    func makeNSView(context: Context) -> KeyboardShortcutNSView {
        let view = KeyboardShortcutNSView()
        updateHandlers(on: view)

        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }

        return view
    }

    func updateNSView(_ nsView: KeyboardShortcutNSView, context: Context) {
        updateHandlers(on: nsView)

        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    private func updateHandlers(on view: KeyboardShortcutNSView) {
        view.onSpace = onSpace
        view.onEscape = onEscape
        view.onFullscreen = onFullscreen
        view.onMute = onMute
        view.onSeekBackward = onSeekBackward
        view.onSeekForward = onSeekForward
    }

    final class KeyboardShortcutNSView: NSView {
        var onEscape: (() -> Void)?
        var onSpace: (() -> Void)?
        var onFullscreen: (() -> Void)?
        var onMute: (() -> Void)?
        var onSeekBackward: (() -> Void)?
        var onSeekForward: (() -> Void)?

        override var acceptsFirstResponder: Bool {
            true
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 {
                onEscape?()
                return
            }

            switch event.charactersIgnoringModifiers?.lowercased() {
            case " ":
                onSpace?()
            case "f":
                onFullscreen?()
            case "m":
                onMute?()
            case String(UnicodeScalar(NSLeftArrowFunctionKey)!):
                onSeekBackward?()
            case String(UnicodeScalar(NSRightArrowFunctionKey)!):
                onSeekForward?()
            default:
                super.keyDown(with: event)
            }
        }
    }
}
#else
struct PlaybackKeyboardShortcutView: View {
    let onEscape: () -> Void
    let onSpace: () -> Void
    let onFullscreen: () -> Void
    let onMute: () -> Void
    let onSeekBackward: () -> Void
    let onSeekForward: () -> Void

    var body: some View {
        EmptyView()
    }
}
#endif

#if os(macOS)
// Keep the dismiss environment dependency in a leaf view. Reading it in a
// screen that also presents a navigation destination can repeatedly invalidate
// that screen during a push and hang SwiftUI's navigation update cycle.
private struct NavigationDismissShortcutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .escapeKeyShortcut { dismiss() }
    }
}
#endif

extension View {
    func escapeKeyDismissShortcut() -> some View {
        #if os(macOS)
        overlay(alignment: .bottomLeading) {
            NavigationDismissShortcutView()
        }
        #else
        self
        #endif
    }

    func escapeKeyShortcut(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        overlay(alignment: .bottomLeading) {
            Button(action: action) {
                EmptyView()
            }
            .keyboardShortcut(.cancelAction)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
        #else
        self
        #endif
    }
}
