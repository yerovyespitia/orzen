import SwiftUI

struct SourceAddonPicker: View {
    @Binding var selection: LocalAddon.ID?
    let addons: [LocalAddon]
    @State private var isHovered = false

    var body: some View {
        Menu {
            Button {
                selection = nil
            } label: {
                if selection == nil {
                    Label("All", systemImage: "checkmark")
                } else {
                    Text("All")
                }
            }

            Divider()

            ForEach(addons) { addon in
                Button {
                    selection = addon.id
                } label: {
                    if addon.id == selectedAddon?.id {
                        Label(addon.sourceSelectionTitle, systemImage: "checkmark")
                    } else {
                        Text(addon.sourceSelectionTitle)
                    }
                }
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
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .help(helpText)
        .accessibilityLabel("Source addon")
        .accessibilityValue(selectedTitle)
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
