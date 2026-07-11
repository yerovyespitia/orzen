import SwiftUI

struct SourceRow: View {
    let source: StreamSource

    var body: some View {
        HStack(alignment: .top, spacing: rowSpacing) {
            ZStack {
                SourceRowStyle.cardShape
                    .fill(Color.white.opacity(0.1))

                Image(systemName: sourceIconName)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))
            }
            .frame(width: artworkWidth, height: artworkHeight)
            .overlay {
                SourceRowStyle.cardShape
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(source.title)
                    .font(titleFont)
                    .foregroundColor(.white)
                    .lineLimit(2)

                if !source.metadata.isEmpty {
                    Text(source.metadata.joined(separator: " • "))
                        .font(metadataFont)
                        .foregroundColor(.white.opacity(0.62))
                        .lineLimit(1)
                }

                compatibilityBadge
                compatibilityDetail

                Text(source.description)
                    .font(descriptionFont)
                    .foregroundColor(.white.opacity(0.78))
                    .lineLimit(descriptionLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(rowPadding)
        .frame(minHeight: minimumHeight, alignment: .top)
        .sourceRowBackground()
    }

    private var artworkWidth: CGFloat {
        #if os(iOS)
        return 58
        #else
        return 190
        #endif
    }

    private var artworkHeight: CGFloat {
        #if os(iOS)
        return 58
        #else
        return 123
        #endif
    }

    private var iconSize: CGFloat {
        #if os(iOS)
        return 22
        #else
        return 28
        #endif
    }

    private var rowSpacing: CGFloat {
        #if os(iOS)
        return 10
        #else
        return 16
        #endif
    }

    private var rowPadding: CGFloat {
        #if os(iOS)
        return 10
        #else
        return 12
        #endif
    }

    private var minimumHeight: CGFloat {
        #if os(iOS)
        return 78
        #else
        return 147
        #endif
    }

    private var titleFont: Font {
        #if os(iOS)
        return .subheadline.weight(.semibold)
        #else
        return .headline
        #endif
    }

    private var metadataFont: Font {
        #if os(iOS)
        return .caption2
        #else
        return .caption
        #endif
    }

    private var descriptionFont: Font {
        #if os(iOS)
        return .caption
        #else
        return .callout
        #endif
    }

    private var descriptionLineLimit: Int {
        #if os(iOS)
        return 2
        #else
        return 3
        #endif
    }

    private var sourceIconName: String {
        #if os(iOS)
        switch NativePlaybackCompatibilityResolver.compatibility(for: source) {
        case .unsupported:
            return "exclamationmark.triangle.fill"
        case .unknown:
            return "questionmark.circle.fill"
        case .supported, .likely:
            return "play.circle.fill"
        }
        #else
        return source.playbackURL == nil ? "exclamationmark.triangle.fill" : "play.circle.fill"
        #endif
    }

    @ViewBuilder
    private var compatibilityBadge: some View {
        #if os(iOS)
        let compatibility = NativePlaybackCompatibilityResolver.compatibility(for: source)
        if let title = compatibility.badgeTitle {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(badgeForeground(for: compatibility))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(badgeBackground(for: compatibility), in: Capsule())
                .overlay {
                    Capsule().stroke(badgeStroke(for: compatibility), lineWidth: 1)
                }
                .help(compatibility.message ?? "This source is compatible with native iOS playback.")
        }
        #endif
    }

    @ViewBuilder
    private var compatibilityDetail: some View {
        #if os(iOS)
        let compatibility = NativePlaybackCompatibilityResolver.compatibility(for: source)
        if shouldShowCompatibilityDetail(for: compatibility),
           let message = compatibility.message {
            Text(message)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.58))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        #endif
    }

    #if os(iOS)
    private func shouldShowCompatibilityDetail(for compatibility: NativePlaybackCompatibility) -> Bool {
        switch compatibility {
        case .unknown:
            return true
        case .supported, .likely, .unsupported:
            return false
        }
    }

    private func badgeForeground(for compatibility: NativePlaybackCompatibility) -> Color {
        switch compatibility {
        case .supported, .likely:
            return .black.opacity(0.84)
        case .unknown:
            return .white.opacity(0.84)
        case .unsupported:
            return .white.opacity(0.76)
        }
    }

    private func badgeBackground(for compatibility: NativePlaybackCompatibility) -> Color {
        switch compatibility {
        case .supported, .likely:
            return .white.opacity(0.86)
        case .unknown:
            return .white.opacity(0.1)
        case .unsupported:
            return .white.opacity(0.065)
        }
    }

    private func badgeStroke(for compatibility: NativePlaybackCompatibility) -> Color {
        switch compatibility {
        case .supported, .likely:
            return .white.opacity(0.18)
        case .unknown:
            return .white.opacity(0.16)
        case .unsupported:
            return .white.opacity(0.11)
        }
    }
    #endif
}

private enum SourceRowStyle {
    static var cornerRadius: CGFloat {
        #if os(iOS)
        return 10
        #else
        return 14
        #endif
    }
    static let cardShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
}

private extension View {
    @ViewBuilder
    func sourceRowBackground() -> some View {
        let shape = SourceRowStyle.cardShape

        if #available(macOS 26, *) {
            self
                .glassEffect(.clear, in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(0.04), lineWidth: 1)
                }
        } else {
            self
                .background(Color.white.opacity(0.045), in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(0.04), lineWidth: 1)
                }
        }
    }
}
