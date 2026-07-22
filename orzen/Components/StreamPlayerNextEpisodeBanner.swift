import SwiftUI

struct StreamPlayerNextEpisodeBanner: View {
    let episodeTitle: String
    let isLoading: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon

                #if os(iOS)
                Text("Next episode")
                    .font(.callout.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                #else
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next episode")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white.opacity(0.68))

                    Text(episodeTitle)
                        .font(.callout.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                #endif

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.74))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, bannerVerticalPadding)
            .frame(width: bannerWidth, alignment: .leading)
            .nextEpisodeBannerBackground(isHovered: isHovered, shape: shape)
            .shadow(color: .black.opacity(0.32), radius: 18, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .contentShape(shape)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.14), value: isHovered)
        .help("Play next episode")
        .accessibilityLabel("Play next episode")
    }

    @ViewBuilder
    private var icon: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
                .frame(width: 30, height: 30)
        } else {
            Image(systemName: "forward.end.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black.opacity(0.82))
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.9), in: Circle())
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    private var bannerWidth: CGFloat {
        #if os(iOS)
        200
        #else
        300
        #endif
    }

    private var bannerVerticalPadding: CGFloat {
        #if os(iOS)
        10
        #else
        12
        #endif
    }
}

private extension View {
    @ViewBuilder
    func nextEpisodeBannerBackground(isHovered: Bool, shape: RoundedRectangle) -> some View {
        if #available(macOS 26, iOS 26, *) {
            self
                .glassEffect(.clear.interactive(), in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(isHovered ? 0.18 : 0.04), lineWidth: 1)
                }
        } else {
            self
                .background(Color.white.opacity(isHovered ? 0.1 : 0.045), in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(isHovered ? 0.18 : 0.04), lineWidth: 1)
                }
        }
    }
}
