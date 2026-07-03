import SwiftUI

struct AddonsView: View {
    @ObservedObject private var addonStore = LocalAddonStore.shared
    @State private var configuringSubtitleAddon: LocalAddon?
    var ownsNavigationStack = true

    var body: some View {
        if ownsNavigationStack {
            NavigationStack {
                content
            }
        } else {
            content
        }
    }

    private var content: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: contentSpacing) {
                header
                addonList
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .navigationTitle(ownsNavigationStack ? "Addons" : "")
        .sheet(item: $configuringSubtitleAddon) { addon in
            SubtitleAddonSettingsView(addonName: addon.name)
        }
        #if os(iOS)
        .toolbar(ownsNavigationStack ? .hidden : .visible, for: .navigationBar)
        .interactivePopGestureEnabled()
        #endif
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Addons")
                    .font(headerTitleFont)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Manage the addons available for your account.")
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()
        }
    }

    private var contentSpacing: CGFloat {
        #if os(iOS)
        return 16
        #else
        return 24
        #endif
    }

    private var headerTitleFont: Font {
        #if os(iOS)
        return .title2
        #else
        return .title
        #endif
    }

    private var addonList: some View {
        VStack(spacing: addonRowSpacing) {
            AddonRow(
                name: "Cinemeta",
                description: "Default addon for catalogs and metadata.",
                category: "Catalogs",
                isRemovable: false,
                isConfigurable: false,
                configurationAction: nil,
                removeAction: nil
            )

            ForEach(addonStore.addons) { addon in
                AddonRow(
                    name: addon.name,
                    description: addon.description,
                    category: addon.resourceSummary,
                    isRemovable: addon.isRemovable,
                    isConfigurable: addon.resources.contains(.subtitles),
                    configurationAction: {
                        configuringSubtitleAddon = addon
                    },
                    removeAction: {
                        addonStore.remove(addon)
                    }
                )
            }
        }
    }

    private var addonRowSpacing: CGFloat {
        #if os(iOS)
        return 10
        #else
        return 16
        #endif
    }
}

private struct AddonRow: View {
    let name: String
    let description: String
    let category: String
    let isRemovable: Bool
    let isConfigurable: Bool
    let configurationAction: (() -> Void)?
    let removeAction: (() -> Void)?

    var body: some View {
        HStack(spacing: rowSpacing) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(iconFont)
                .foregroundColor(.white)
                .frame(width: iconSize, height: iconSize)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: iconCornerRadius))

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(titleFont)
                    .foregroundColor(.white)

                Text(description)
                    .font(descriptionFont)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)

                Text(category)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.58))

                if !isRemovable {
                    Text("This addon cannot be removed.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()

            actionButtons
        }
        .padding(rowPadding)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: rowCornerRadius))
    }

    private var rowSpacing: CGFloat {
        #if os(iOS)
        return 12
        #else
        return 16
        #endif
    }

    private var rowPadding: CGFloat {
        #if os(iOS)
        return 14
        #else
        return 20
        #endif
    }

    private var rowCornerRadius: CGFloat {
        #if os(iOS)
        return 14
        #else
        return 18
        #endif
    }

    private var iconFont: Font {
        #if os(iOS)
        return .headline
        #else
        return .title2
        #endif
    }

    private var iconSize: CGFloat {
        #if os(iOS)
        return 36
        #else
        return 44
        #endif
    }

    private var iconCornerRadius: CGFloat {
        #if os(iOS)
        return 10
        #else
        return 12
        #endif
    }

    private var titleFont: Font {
        #if os(iOS)
        return .subheadline.weight(.semibold)
        #else
        return .headline
        #endif
    }

    private var descriptionFont: Font {
        #if os(iOS)
        return .caption
        #else
        return .body
        #endif
    }

    @ViewBuilder
    private var actionButtons: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 4) {
                actionButtonContent
            }
        } else {
            actionButtonContent
        }
    }

    private var actionButtonContent: some View {
        HStack(spacing: 4) {
            AddonActionButton(
                systemName: "gearshape",
                isEnabled: isConfigurable,
                help: "Configure addon"
            ) {
                configurationAction?()
            }

            AddonActionButton(
                systemName: "minus.circle",
                isEnabled: isRemovable,
                help: "Remove addon"
            ) {
                removeAction?()
            }
        }
    }
}

private struct AddonActionButton: View {
    let systemName: String
    let isEnabled: Bool
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        if #available(macOS 26, *) {
            Button(action: action) {
                icon
                    .background(buttonBackground)
                    .glassEffect(isEnabled ? .regular.interactive() : .regular, in: Circle())
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .onHover { hovering in
                isHovered = hovering && isEnabled
            }
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .help(help)
            .accessibilityLabel(help)
            .disabled(!isEnabled)
        } else {
            Button(action: action) {
                icon
                    .background(buttonBackground)
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .onHover { hovering in
                isHovered = hovering && isEnabled
            }
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .help(help)
            .accessibilityLabel(help)
            .disabled(!isEnabled)
        }
    }

    private var icon: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white.opacity(isEnabled ? 0.86 : 0.28))
            .frame(width: 32, height: 32)
    }

    private var buttonBackground: some View {
        Circle()
            .fill(Color.white.opacity(isHovered ? 0.16 : 0.08))
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(isHovered ? 0.14 : 0.06), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.42)
    }
}

private struct SubtitleAddonSettingsView: View {
    let addonName: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var preferences = SubtitlePreferencesStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(addonName)
                        .font(.title2.weight(.semibold))

                    Text("Subtitle languages")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                SubtitleSettingsCloseButton {
                    dismiss()
                }
            }

            VStack(spacing: 0) {
                ForEach(SubtitlePreferencesStore.availableLanguages) { option in
                    SubtitleLanguageRow(
                        option: option,
                        isSelected: Binding(
                            get: {
                                preferences.isSelected(option)
                            },
                            set: { isSelected in
                                preferences.setSelected(isSelected, for: option)
                            }
                        )
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Spacer(minLength: 0)
        }
        .padding(settingsPadding)
        .frame(width: settingsWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents(presentationDetents)
        #if os(iOS)
        .presentationDragIndicator(.visible)
        #endif
        .background(.thinMaterial)
        .presentationBackground(.thinMaterial)
    }

    private var settingsPadding: CGFloat {
        #if os(iOS)
        return 20
        #else
        return 24
        #endif
    }

    private var settingsWidth: CGFloat? {
        #if os(iOS)
        return nil
        #else
        return 420
        #endif
    }

    private var presentationDetents: Set<PresentationDetent> {
        #if os(iOS)
        return [.height(330)]
        #else
        return [.height(300)]
        #endif
    }
}

private struct SubtitleSettingsCloseButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        if #available(macOS 26, *) {
            Button(action: action) {
                icon
                    .background(buttonBackground)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .help("Close")
            .accessibilityLabel("Close")
        } else {
            Button(action: action) {
                icon
                    .background(buttonBackground)
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .help("Close")
            .accessibilityLabel("Close")
        }
    }

    private var icon: some View {
        Image(systemName: "xmark")
            .font(.system(size: closeIconSize, weight: .bold))
            .foregroundColor(.primary.opacity(isHovered ? 0.86 : 0.72))
            .frame(width: closeButtonSize, height: closeButtonSize)
    }

    private var closeIconSize: CGFloat {
        #if os(iOS)
        return 18
        #else
        return 12
        #endif
    }

    private var closeButtonSize: CGFloat {
        #if os(iOS)
        return 44
        #else
        return 28
        #endif
    }

    private var buttonBackground: some View {
        Circle()
            .fill(Color.primary.opacity(isHovered ? 0.12 : 0.08))
            .overlay(
                Circle()
                    .stroke(Color.primary.opacity(isHovered ? 0.12 : 0.06), lineWidth: 1)
            )
    }
}

private struct SubtitleLanguageRow: View {
    let option: SubtitleLanguageOption
    @Binding var isSelected: Bool

    var body: some View {
        HStack {
            Text(option.title)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)

            Spacer()

            Toggle("", isOn: $isSelected)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.green)
        }
        .padding(.horizontal, 20)
        .frame(height: 54)
        .overlay(alignment: .bottom) {
            if option.id != SubtitlePreferencesStore.availableLanguages.last?.id {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)
                    .padding(.leading, 20)
            }
        }
    }
}
