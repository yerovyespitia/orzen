import SwiftUI

extension View {
    @ViewBuilder
    func orzenTopScrollEdgeEffect() -> some View {
        #if os(iOS)
        modifier(OrzenTopScrollEdgeEffectModifier())
        #else
        self
        #endif
    }
}

#if os(iOS)
private struct OrzenTopScrollEdgeEffectModifier: ViewModifier {
    @State private var showsFade = false

    func body(content: Content) -> some View {
        tracked(content)
            .overlay(alignment: .top) {
                if showsFade {
                    OrzenTopScrollEdgeFade()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
    }

    @ViewBuilder
    private func tracked(_ content: Content) -> some View {
        if #available(iOS 18.0, *) {
            styled(content)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > 4
                } action: { _, newValue in
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showsFade = newValue
                    }
                }
        } else {
            styled(content)
        }
    }

    @ViewBuilder
    private func styled(_ content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

private struct OrzenTopScrollEdgeFade: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.86),
                Color.black.opacity(0.58),
                Color.black.opacity(0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 150)
        .ignoresSafeArea(.container, edges: .top)
    }
}
#endif
