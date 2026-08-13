import SwiftUI

struct SourceAddonPicker: View {
    @Binding var selection: LocalAddon.ID?
    let addons: [LocalAddon]
    let onMenuRequested: (() -> Void)?
    @State private var isHovered = false
    @State private var isMenuPresented = false

    init(
        selection: Binding<LocalAddon.ID?>,
        addons: [LocalAddon],
        onMenuRequested: (() -> Void)? = nil
    ) {
        _selection = selection
        self.addons = addons
        self.onMenuRequested = onMenuRequested
    }

    var body: some View {
        Button {
            if let onMenuRequested {
                onMenuRequested()
            } else {
                isMenuPresented.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedTitle)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 14)
            .frame(minHeight: controlHeight)
            .background(controlBackground)
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(isHovered ? 0.16 : 0.08), lineWidth: 1)
            }
            .modifier(SourceAddonPickerGlassSurface())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .help(helpText)
        .accessibilityLabel("Source addon")
        .accessibilityValue(selectedTitle)
        .background {
            if onMenuRequested != nil {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: SourceAddonPickerFramePreferenceKey.self,
                        value: proxy.frame(in: .named(SourceAddonPickerCoordinateSpace.name))
                    )
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if onMenuRequested == nil && isMenuPresented {
                SourceAddonPickerMenu(
                    selection: $selection,
                    addons: addons,
                    dismiss: { isMenuPresented = false }
                )
                .offset(y: controlHeight + 8)
                .zIndex(1)
            }
        }
    }

    private var selectedAddon: LocalAddon? {
        guard let selection else { return nil }
        return addons.first(where: { $0.id == selection })
    }

    private var controlBackground: some View {
        Capsule()
            .fill(Color.white.opacity(isHovered ? 0.16 : 0.08))
    }

    private var helpText: String {
        "Source addon: \(selectedTitle)"
    }

    private var selectedTitle: String {
        guard selection != nil else { return "All" }
        return selectedAddon?.sourceSelectionTitle ?? "All"
    }

    private var controlHeight: CGFloat {
        #if os(iOS)
        return 44
        #else
        return 32
        #endif
    }
}

enum SourceAddonPickerCoordinateSpace {
    static let name = "source-addon-picker-coordinate-space"
}

struct SourceAddonPickerFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let nextFrame = nextValue()
        if nextFrame != .zero {
            value = nextFrame
        }
    }
}

struct SourceAddonPickerMenu: View {
    @Binding var selection: LocalAddon.ID?
    let addons: [LocalAddon]
    let dismiss: () -> Void
    @State private var hoveredOption: HoveredOption?

    var body: some View {
        ScrollView(.vertical, showsIndicators: needsScrolling) {
            VStack(alignment: .leading, spacing: 2) {
                option(title: "All", id: nil, hoverID: .all)

                Divider()
                    .padding(.vertical, 4)

                ForEach(addons) { addon in
                    option(
                        title: addon.sourceSelectionTitle,
                        id: addon.id,
                        hoverID: .addon(addon.id)
                    )
                }
            }
            .padding(6)
        }
        .frame(width: 260)
        .frame(height: menuHeight)
        .padding(4)
        .modifier(SourceAddonPickerMenuSurface())
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
    }

    private var menuHeight: CGFloat {
        min(contentHeight, maximumHeight)
    }

    private var needsScrolling: Bool {
        contentHeight > maximumHeight
    }

    private var contentHeight: CGFloat {
        let optionCount = CGFloat(addons.count + 1)
        let optionHeights = optionCount * 30
        let spacing = optionCount * 2
        let dividerAndPadding: CGFloat = 9
        let contentPadding: CGFloat = 12
        return optionHeights + spacing + dividerAndPadding + contentPadding
    }

    private var maximumHeight: CGFloat { 792 }

    private func option(
        title: String,
        id: LocalAddon.ID?,
        hoverID: HoveredOption
    ) -> some View {
        Button {
            selection = id
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .opacity(selection == id ? 1 : 0)
                    .frame(width: 14)

                Text(title)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 30)
            .background(
                Color.white.opacity(hoveredOption == hoverID ? 0.12 : 0),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredOption = hovering ? hoverID : nil
        }
        .animation(.easeInOut(duration: 0.1), value: hoveredOption)
    }

    private enum HoveredOption: Equatable {
        case all
        case addon(LocalAddon.ID)
    }
}

private struct SourceAddonPickerMenuSurface: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, iOS 26, *) {
            GlassEffectContainer(spacing: 0) {
                content
                    .glassEffect(
                        .clear.tint(Color.black.opacity(0.16)),
                        in: shape
                    )
            }
            .overlay {
                shape.stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
        }
    }
}

private struct SourceAddonPickerGlassSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, iOS 26, *) {
            content.glassEffect(.clear.interactive(), in: Capsule())
        } else {
            content
        }
    }
}
