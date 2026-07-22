import SwiftUI

struct ProfileSelectionView: View {
    let onSelect: () -> Void

    private let profiles = [
        ProfileOption(name: "Luna", emoji: "🌙"),
        ProfileOption(name: "Mateo", emoji: "🎧"),
        ProfileOption(name: "Nico", emoji: "⚡️")
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.09),
                    Color.clear,
                    Color.white.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 54) {
                Text("Who's watching?")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundColor(.white)

                HStack(spacing: 52) {
                    ForEach(profiles) { profile in
                        ProfileCircleButton(profile: profile) {
                            withAnimation(.easeInOut(duration: 0.28)) {
                                onSelect()
                            }
                        }
                    }
                }
            }
            .padding(48)
        }
    }
}

private struct ProfileOption: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
}

private struct ProfileCircleButton: View {
    let profile: ProfileOption
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 18) {
                profileAvatar

                Text(profile.name)
                    .font(.title3.weight(.medium))
                    .foregroundColor(.white.opacity(isHovered ? 1 : 0.72))
            }
            .scaleEffect(isHovered ? 1.08 : 1)
            .offset(y: isHovered ? -8 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHovered)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(profile.name)
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            Text(profile.emoji)
                .font(.system(size: 66))
                .frame(width: 184, height: 184)
                .glassEffect(.clear.interactive(), in: Circle())
        } else {
            Text(profile.emoji)
                .font(.system(size: 66))
                .frame(width: 184, height: 184)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
        }
    }
}

#Preview {
    ProfileSelectionView { }
        .frame(width: 1280, height: 780)
}
