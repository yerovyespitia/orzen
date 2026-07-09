import SwiftUI

struct PlayerFlatSlider: View {
    @Binding var value: Double

    let bounds: ClosedRange<Double>
    let accessibilityLabel: String
    let expandsWhileInteracting: Bool
    let onInteractionChange: (Bool) -> Void

    @State private var isDragging = false
    #if os(macOS)
    @State private var isPointerHovering = false
    #endif

    init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double>,
        accessibilityLabel: String,
        expandsWhileInteracting: Bool = false,
        onInteractionChange: @escaping (Bool) -> Void = { _ in }
    ) {
        _value = value
        self.bounds = bounds
        self.accessibilityLabel = accessibilityLabel
        self.expandsWhileInteracting = expandsWhileInteracting
        self.onInteractionChange = onInteractionChange
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let sliderProgress = progress(for: value)

            ZStack {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.22))

                    Capsule()
                        .fill(.white.opacity(0.95))
                        .frame(width: max(currentTrackHeight, width * sliderProgress))
                }
                .frame(height: currentTrackHeight)
            }
            .frame(width: width, height: proxy.size.height)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            onInteractionChange(true)
                        }
                        isDragging = true
                        value = value(for: gesture.location.x, width: width)
                    }
                    .onEnded { _ in
                        isDragging = false
                        DispatchQueue.main.async {
                            onInteractionChange(false)
                        }
                    }
            )
            #if os(macOS)
            .onHover { isHovering in
                isPointerHovering = isHovering
            }
            #endif
            .animation(.easeInOut(duration: 0.16), value: isExpanded)
        }
        .frame(height: interactionHeight)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            adjustValue(direction)
        }
    }

    private var accessibilityValue: String {
        "\(Int(progress(for: value) * 100)) percent"
    }

    private var isExpanded: Bool {
        guard expandsWhileInteracting else { return false }

        #if os(macOS)
        return isDragging || isPointerHovering
        #else
        return isDragging
        #endif
    }

    private var currentTrackHeight: CGFloat {
        isExpanded ? 12 : 7
    }

    private var interactionHeight: CGFloat {
        guard expandsWhileInteracting else { return currentTrackHeight }

        #if os(iOS)
        return 44
        #else
        return 28
        #endif
    }

    private func progress(for value: Double) -> Double {
        let lower = bounds.lowerBound
        let upper = bounds.upperBound
        guard upper > lower else { return 0 }

        let clampedValue = min(max(value, lower), upper)
        return (clampedValue - lower) / (upper - lower)
    }

    private func value(for locationX: CGFloat, width: CGFloat) -> Double {
        let progress = min(max(Double(locationX / max(width, 1)), 0), 1)
        return bounds.lowerBound + ((bounds.upperBound - bounds.lowerBound) * progress)
    }

    private func adjustValue(_ direction: AccessibilityAdjustmentDirection) {
        let step = (bounds.upperBound - bounds.lowerBound) / 20

        onInteractionChange(true)
        switch direction {
        case .increment:
            value = min(value + step, bounds.upperBound)
        case .decrement:
            value = max(value - step, bounds.lowerBound)
        @unknown default:
            break
        }
        onInteractionChange(false)
    }
}
