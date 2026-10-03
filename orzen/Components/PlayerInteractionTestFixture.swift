#if DEBUG && os(iOS)
import SwiftUI

// A deterministic, paused player using the production view and gesture layers.
// No stream, decoder, or network dependency is needed to test touch routing.
enum PlayerInteractionTestFixture {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--player-interaction-tests")
    }

    static func makePlayer() -> StreamPlayerView {
        let source = StreamSource(
            id: "player-interaction-fixture",
            addonName: "UI Tests",
            title: "Gesture fixture",
            description: "",
            metadata: [],
            sourceCategory: .general,
            playbackURL: nil
        )
        return StreamPlayerView(
            interactionTestRequest: StreamPlaybackRequest(
                source: source,
                title: "Gesture fixture",
                subtitle: "",
                contentID: "player-interaction-fixture",
                contentType: .movie
            )
        )
    }
}

extension StreamPlayerView {
    @ViewBuilder
    var interactionTestState: some View {
        if PlayerInteractionTestFixture.isEnabled {
            VStack {
                Text(String(format: "%.2f", Double(effectiveVideoScale)))
                    .accessibilityIdentifier("player-test-scale")
                Text(isChromePresented ? "visible" : "hidden")
                    .accessibilityIdentifier("player-test-chrome")
                Text(String(Int(currentTime)))
                    .accessibilityIdentifier("player-test-time")
            }
            .font(.caption2)
            .foregroundStyle(.white)
            .allowsHitTesting(false)
        }
    }
}
#endif
