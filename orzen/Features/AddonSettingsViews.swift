import SwiftUI

struct AddonManifestEditorView: View {
    let addon: LocalAddon

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var addonStore = LocalAddonStore.shared
    @State private var manifestURLString: String
    @State private var saveErrorMessage: String?
    @State private var isSaving = false

    init(addon: LocalAddon) {
        self.addon = addon
        _manifestURLString = State(initialValue: addon.manifestURL.absoluteString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            urlEditor
            saveRow
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

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(addon.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Manifest URL")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            AddonSettingsCloseButton {
                dismiss()
            }
        }
    }

    private var urlEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(inputBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(inputStrokeColor, lineWidth: 1)
                    }

                TextField("https://example.com/manifest.json", text: $manifestURLString)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .tint(.primary)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .submitLabel(.done)
                    .onSubmit(saveIfPossible)
                    .padding(.horizontal, 14)
            }
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let saveErrorMessage {
                Text(saveErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var saveRow: some View {
        HStack {
            Spacer()

            Button {
                saveIfPossible()
            } label: {
                Text(isSaving ? "Saving" : "Save")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(saveButtonForeground)
                    .frame(minWidth: 94)
                    .frame(height: 46)
                    .background(saveButtonBackground, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(saveButtonStroke, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(validatedManifestURL == nil || isSaving)
        }
    }

    private var inputBackground: some ShapeStyle {
        Color.primary.opacity(0.06)
    }

    private var inputStrokeColor: Color {
        Color.primary.opacity(0.1)
    }

    private var saveButtonForeground: Color {
        guard validatedManifestURL != nil, !isSaving else {
            return .secondary.opacity(0.7)
        }

        #if os(macOS)
        return .black.opacity(0.82)
        #else
        return .white
        #endif
    }

    private var saveButtonBackground: Color {
        guard validatedManifestURL != nil, !isSaving else {
            return .primary.opacity(0.08)
        }

        #if os(macOS)
        return .white.opacity(0.88)
        #else
        return .primary
        #endif
    }

    private var saveButtonStroke: Color {
        Color.primary.opacity(validatedManifestURL == nil || isSaving ? 0.08 : 0.16)
    }

    private var trimmedManifestURLString: String {
        manifestURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validatedManifestURL: URL? {
        guard let url = URL(string: trimmedManifestURLString),
              ["http", "https"].contains(url.scheme?.lowercased()),
              url.host != nil else {
            return nil
        }

        return url
    }

    private var validationMessage: String? {
        guard !trimmedManifestURLString.isEmpty else { return nil }
        guard validatedManifestURL == nil else { return nil }
        return "Enter a valid HTTP or HTTPS manifest URL."
    }

    private func saveIfPossible() {
        guard let validatedManifestURL, !isSaving else { return }

        isSaving = true
        saveErrorMessage = nil

        Task {
            do {
                try await addonStore.updateManifestURL(for: addon, manifestURL: validatedManifestURL)
                dismiss()
            } catch {
                saveErrorMessage = "This URL did not return a compatible Stremio manifest."
                isSaving = false
            }
        }
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
        return 460
        #endif
    }

    private var presentationDetents: Set<PresentationDetent> {
        #if os(iOS)
        return [.height(280)]
        #else
        return [.height(250)]
        #endif
    }
}

struct SubtitleAddonSettingsView: View {
    let addonName: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var preferences = SubtitlePreferencesStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            languageList
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

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(addonName)
                    .font(.title2.weight(.semibold))

                Text("Subtitle languages")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            AddonSettingsCloseButton {
                dismiss()
            }
        }
    }

    private var languageList: some View {
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

struct AddonSettingsCloseButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        if #available(macOS 26, *) {
            Button(action: action) {
                icon
                    .glassEffect(.clear.interactive(), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
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
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
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
        return 18
        #endif
    }

    private var closeButtonSize: CGFloat {
        #if os(iOS)
        return 44
        #else
        return 44
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
