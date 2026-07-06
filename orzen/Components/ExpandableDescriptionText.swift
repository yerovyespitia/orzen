import SwiftUI

struct ExpandableDescriptionText: View {
    let text: String

    @State private var isExpanded = false
    @State private var fullTextHeight: CGFloat = 0
    @State private var collapsedTextHeight: CGFloat = 0

    private let collapsedLineLimit = 3

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                descriptionText
                    .lineLimit(isExpanded ? nil : collapsedLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .mask(descriptionMask)

                if shouldShowExpansionControl && !isExpanded {
                    toggleButton(systemImage: "chevron.down")
                        .padding(.bottom, 1)
                }
            }

            if shouldShowExpansionControl && isExpanded {
                toggleButton(systemImage: "chevron.up")
            }
        }
        .background(fullHeightReader)
        .background(collapsedHeightReader)
    }

    private var descriptionText: some View {
        Text(text)
            .font(.body)
            .foregroundColor(.white.opacity(0.86))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var descriptionMask: some View {
        if shouldShowExpansionControl && !isExpanded {
            LinearGradient(
                colors: [
                    Color.white,
                    Color.white,
                    Color.white.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            Rectangle()
        }
    }

    private func toggleButton(systemImage: String) -> some View {
        Button {
            var transaction = Transaction()
            transaction.disablesAnimations = true

            withTransaction(transaction) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white.opacity(0.88))
                .frame(width: 44, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Show less description" : "Show full description")
    }

    private var fullHeightReader: some View {
        measuredDescriptionText(lineLimit: nil)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: FullDescriptionHeightKey.self, value: proxy.size.height)
                }
            )
            .opacity(0)
            .accessibilityHidden(true)
            .onPreferenceChange(FullDescriptionHeightKey.self) { height in
                fullTextHeight = height
            }
    }

    private var collapsedHeightReader: some View {
        measuredDescriptionText(lineLimit: collapsedLineLimit)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: CollapsedDescriptionHeightKey.self, value: proxy.size.height)
                }
            )
            .opacity(0)
            .accessibilityHidden(true)
            .onPreferenceChange(CollapsedDescriptionHeightKey.self) { height in
                collapsedTextHeight = height
            }
    }

    private func measuredDescriptionText(lineLimit: Int?) -> some View {
        Text(text)
            .font(.body)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shouldShowExpansionControl: Bool {
        fullTextHeight > collapsedTextHeight + 1
    }
}

private struct FullDescriptionHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CollapsedDescriptionHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
