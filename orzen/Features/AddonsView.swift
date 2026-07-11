import SwiftUI

struct AddonsView: View {
    @ObservedObject private var addonStore = LocalAddonStore.shared
    @State private var isAddingAddon = false
    @State private var configuringSubtitleAddon: LocalAddon?
    @State private var editingAddon: LocalAddon?
    @State private var addonPendingRemoval: LocalAddon?
    var ownsNavigationStack = true
    var popToRootRequest = 0
    private let contentHorizontalPadding: CGFloat = 16
    private let contentTopPadding: CGFloat = 8

    var body: some View {
        if ownsNavigationStack {
            NavigationStack {
                content
                    #if os(iOS)
                    .popNavigationToRoot(on: popToRootRequest)
                    #endif
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

                ScrollView {
                    addonList
                        .padding(.bottom, 24)
                }
                .orzenTopScrollEdgeEffect()
            }
            .padding(.horizontal, contentHorizontalPadding)
            .padding(.top, contentTopPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(ownsNavigationStack ? "Addons" : "")
        .sheet(item: $configuringSubtitleAddon) { addon in
            SubtitleAddonSettingsView(addonName: addon.name)
        }
        .sheet(item: $editingAddon) { addon in
            AddonManifestEditorView(addon: addon)
        }
        .sheet(isPresented: $isAddingAddon) {
            AddonManifestInstallView()
        }
        .alert("Remove addon?", isPresented: isConfirmingAddonRemoval) {
            Button("Cancel", role: .cancel) {
                addonPendingRemoval = nil
            }
            Button("Remove", role: .destructive, action: removePendingAddon)
        } message: {
            Text("This addon will be removed from Orzen on this device.")
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
            }

            Spacer()

            AddonActionButton(
                systemName: "plus",
                isEnabled: true,
                help: "Add addon"
            ) {
                isAddingAddon = true
            }
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
                editAction: nil,
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
                    editAction: {
                        editingAddon = addon
                    },
                    configurationAction: {
                        configuringSubtitleAddon = addon
                    },
                    removeAction: {
                        addonPendingRemoval = addon
                    }
                )
            }
        }
    }

    private var isConfirmingAddonRemoval: Binding<Bool> {
        Binding(
            get: { addonPendingRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    addonPendingRemoval = nil
                }
            }
        )
    }

    private func removePendingAddon() {
        guard let addonPendingRemoval else { return }
        addonStore.remove(addonPendingRemoval)
        self.addonPendingRemoval = nil
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
    let editAction: (() -> Void)?
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
        .background(Color.white.opacity(0.1))
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
        return 8
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
                systemName: "square.and.pencil",
                isEnabled: editAction != nil,
                help: "Edit addon URL"
            ) {
                editAction?()
            }

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
                    .glassEffect(isEnabled ? .clear.interactive() : .clear, in: Circle())
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
