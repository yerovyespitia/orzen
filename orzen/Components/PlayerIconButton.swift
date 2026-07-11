import SwiftUI

struct PlayerIconButton: View {
    let systemName: String
    let help: String
    var isEnabled = true
    var usesGlassBackground = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(isEnabled ? 0.92 : 0.38))
                .frame(width: buttonSize, height: buttonSize)
                .modifier(PlayerLiquidGlassCircleSurface(isActive: usesGlassBackground))
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .help(help)
        .accessibilityLabel(help)
        .disabled(!isEnabled)
    }

    private var buttonSize: CGFloat {
        #if os(iOS)
        return usesGlassBackground ? 44 : 34
        #else
        return 28
        #endif
    }
}

struct PlayerLiquidGlassCircleSurface: ViewModifier {
    let isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            #if os(iOS)
            if #available(iOS 26, *) {
                content.glassEffect(interactiveGlass, in: Circle())
            } else {
                fallbackSurface(content)
            }
            #elseif os(macOS)
            if #available(macOS 26, *) {
                content.glassEffect(interactiveGlass, in: Circle())
            } else {
                fallbackSurface(content)
            }
            #else
            content
            #endif
        } else {
            content
        }
    }

    private func fallbackSurface(_ content: Content) -> some View {
        content
            .background {
                Circle()
                    .fill(.black.opacity(0.28))
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.16), lineWidth: 1)
                    }
            }
    }

    @available(iOS 26, macOS 26, *)
    private var interactiveGlass: Glass {
        .clear.interactive()
    }
}
