import SwiftUI

struct AddonManifestInstallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var addonStore = LocalAddonStore.shared
    @State private var manifestURLString = ""
    @State private var saveErrorMessage: String?
    @State private var isSaving = false

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
                Text("Add Addon")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Stremio manifest URL")
                    .foregroundStyle(.white.opacity(0.62))
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
                    .fill(Color.white.opacity(0.075))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    }

                TextField("https://example.com/manifest.json", text: $manifestURLString)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(.white)
                    .tint(.white)
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
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let saveErrorMessage {
                Text(saveErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
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
                Text(isSaving ? "Saving" : "Add")
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

    private var saveButtonForeground: Color {
        validatedManifestURL == nil || isSaving ? .white.opacity(0.34) : .black.opacity(0.86)
    }

    private var saveButtonBackground: Color {
        validatedManifestURL == nil || isSaving ? .white.opacity(0.08) : .white.opacity(0.9)
    }

    private var saveButtonStroke: Color {
        validatedManifestURL == nil || isSaving ? .white.opacity(0.08) : .white.opacity(0.18)
    }

    private func saveIfPossible() {
        guard let validatedManifestURL, !isSaving else { return }

        isSaving = true
        saveErrorMessage = nil

        Task {
            do {
                try await addonStore.addManifestURL(validatedManifestURL)
                dismiss()
            } catch {
                saveErrorMessage = "This URL did not return a compatible stream or subtitles manifest."
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
