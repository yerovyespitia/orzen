import SwiftUI

struct FeaturedCarouselPageIndicator: View {
    let count: Int
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    Circle()
                        .fill(Color.white.opacity(index == selectedIndex ? 0.95 : 0.36))
                        .frame(
                            width: index == selectedIndex ? 8 : 6,
                            height: index == selectedIndex ? 8 : 6
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.18), lineWidth: 0.5)
                        )
                        .frame(width: 18, height: 20)
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .accessibilityLabel("Show featured title \(index + 1) of \(count)")
                .accessibilityValue(index == selectedIndex ? "Current" : "")
                #if os(macOS)
                .help("Show featured title \(index + 1) of \(count)")
                #endif
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.24))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
    }
}
