import SwiftUI

struct PlayerSettingsMenu: View {
    let subtitleDelay: Double
    let canAdjustSubtitleDelay: Bool
    let onSubtitleDelayChange: (Double) -> Void
    @State private var isPresented = false
    @State private var dragStartDelay: Double?

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))
                .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(helpText)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            subtitleDelayControls
                .presentationCompactAdaptation(.popover)
        }
    }

    private let delayStep = 0.5
    private let minimumDelay = -10.0
    private let maximumDelay = 10.0

    private var iconSize: CGFloat {
        #if os(iOS)
        return 20
        #else
        return 14
        #endif
    }

    private var buttonSize: CGFloat {
        #if os(iOS)
        return 46
        #else
        return 28
        #endif
    }

    private var formattedDelay: String {
        String(format: "%+.1f s", subtitleDelay)
    }

    private var subtitleDelayControls: some View {
        VStack(spacing: 14) {
            Text("Subtitle delay")
                .font(.headline.weight(.semibold))

            HStack(spacing: 16) {
                delayButton(
                    systemName: "plus",
                    accessibilityLabel: "Delay subtitles by 0.5 seconds",
                    isEnabled: canAdjustSubtitleDelay && subtitleDelay < maximumDelay
                ) {
                    onSubtitleDelayChange(subtitleDelay + delayStep)
                }

                Text(formattedDelay)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 70)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .gesture(subtitleDelayDragGesture)
                    .accessibilityHint("Swipe left or right to adjust by 0.1 seconds")

                delayButton(
                    systemName: "minus",
                    accessibilityLabel: "Advance subtitles by 0.5 seconds",
                    isEnabled: canAdjustSubtitleDelay && subtitleDelay > minimumDelay
                ) {
                    onSubtitleDelayChange(subtitleDelay - delayStep)
                }
            }

            if !canAdjustSubtitleDelay {
                Text("Available for external subtitles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
    }

    private func delayButton(
        systemName: String,
        accessibilityLabel: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 34, height: 34)
                .background(.quaternary, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .disabled(!isEnabled)
    }

    private var helpText: String {
        canAdjustSubtitleDelay
            ? "Settings. Subtitle delay: \(formattedDelay)"
            : "Settings. Subtitle delay is available for external subtitles"
    }

    private var subtitleDelayDragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard canAdjustSubtitleDelay else { return }

                let initialDelay = dragStartDelay ?? subtitleDelay
                if dragStartDelay == nil {
                    dragStartDelay = initialDelay
                }

                let tenths = Double((value.translation.width / pointsPerTenth).rounded())
                let adjustedDelay = initialDelay - (tenths / 10)
                let clampedDelay = min(max(adjustedDelay, minimumDelay), maximumDelay)
                onSubtitleDelayChange(clampedDelay)
            }
            .onEnded { _ in
                dragStartDelay = nil
            }
    }

    private var pointsPerTenth: CGFloat {
        8
    }
}
