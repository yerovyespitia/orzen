import SwiftUI

struct SettingsView: View {
    @AppStorage(PlaybackSeekInterval.storageKey)
    private var seekIntervalSeconds = PlaybackSeekInterval.defaultValue.rawValue

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var seekIntervalBinding: Binding<Int> {
        Binding(
            get: {
                PlaybackSeekInterval.resolved(rawValue: seekIntervalSeconds).rawValue
            },
            set: { newValue in
                seekIntervalSeconds = PlaybackSeekInterval.resolved(rawValue: newValue).rawValue
            }
        )
    }

    var body: some View {
        #if os(macOS)
        macSettings
        #else
        iPhoneSettings
        #endif
    }

    #if os(macOS)
    private var macSettings: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Settings")
                        .font(.largeTitle.bold())

                    SettingsCardSection(title: "General") {
                        SettingsRow(
                            title: "Language",
                            systemImage: "globe",
                            value: "English",
                            cardStyle: true,
                            showsDivider: true
                        )

                        SettingsRow(
                            title: "Start Screen",
                            systemImage: "rectangle.inset.filled",
                            value: "Home",
                            cardStyle: true
                        )
                    }

                    SettingsCardSection(title: "Playback") {
                        SettingsRow(
                            title: "Preferred Player",
                            systemImage: "play.rectangle",
                            value: "Automatic",
                            cardStyle: true,
                            showsDivider: true
                        )

                        SettingsRow(
                            title: "Streaming Quality",
                            systemImage: "4k.tv",
                            value: "Best Available",
                            cardStyle: true,
                            showsDivider: true
                        )

                        SettingsRow(
                            title: "Autoplay Next Episode",
                            systemImage: "forward.end",
                            value: "On",
                            cardStyle: true,
                            showsDivider: true
                        )

                        SettingsPickerRow(
                            title: "Seek Interval",
                            systemImage: "gobackward",
                            selection: seekIntervalBinding,
                            cardStyle: true
                        )
                    }

                    SettingsCardSection(title: "About") {
                        SettingsRow(
                            title: "Version",
                            systemImage: "info.circle",
                            value: currentVersion,
                            cardStyle: true
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
            }
            .background(Color.black)
            .navigationTitle("Settings")
        }
        .background(Color.black)
    }
    #else
    private var iPhoneSettings: some View {
        NavigationStack {
            List {
                Section("General") {
                    SettingsRow(
                        title: "Language",
                        systemImage: "globe",
                        value: "English"
                    )

                    SettingsRow(
                        title: "Start Screen",
                        systemImage: "rectangle.inset.filled",
                        value: "Home"
                    )
                }

                Section("Playback") {
                    SettingsRow(
                        title: "Preferred Player",
                        systemImage: "play.rectangle",
                        value: "Automatic"
                    )

                    SettingsRow(
                        title: "Streaming Quality",
                        systemImage: "4k.tv",
                        value: "Best Available"
                    )

                    SettingsRow(
                        title: "Autoplay Next Episode",
                        systemImage: "forward.end",
                        value: "On"
                    )

                    SettingsPickerRow(
                        title: "Seek Interval",
                        systemImage: "gobackward",
                        selection: seekIntervalBinding
                    )
                }

                Section("About") {
                    SettingsRow(
                        title: "Version",
                        systemImage: "info.circle",
                        value: currentVersion
                    )
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Settings")
        }
    }
    #endif
}

private struct SettingsRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    var value: String?
    var cardStyle = false
    var showsDivider = false

    init(
        title: LocalizedStringKey,
        systemImage: String,
        value: String? = nil,
        cardStyle: Bool = false,
        showsDivider: Bool = false
    ) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.cardStyle = cardStyle
        self.showsDivider = showsDivider
    }

    var body: some View {
        HStack(spacing: 12) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(.blue)
            }
            .font(rowFont)

            Spacer(minLength: 16)

            if let value {
                Text(value)
                    .font(rowFont)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, cardStyle ? 20 : 0)
        .padding(.vertical, cardStyle ? 0 : rowVerticalPadding)
        .frame(minHeight: cardStyle ? 58 : nil)
        .overlay(alignment: .bottom) {
            if cardStyle && showsDivider {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
                    .padding(.leading, 58)
                    .padding(.trailing, 20)
            }
        }
    }

    private var rowFont: Font {
        #if os(macOS)
        return cardStyle ? .system(size: 15) : .body
        #else
        return .body
        #endif
    }

    private var rowVerticalPadding: CGFloat {
        #if os(iOS)
        return 4
        #else
        return 2
        #endif
    }
}

private struct SettingsPickerRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    @Binding var selection: Int
    var cardStyle = false
    var showsDivider = false

    var body: some View {
        HStack(spacing: 12) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(.blue)
            }
            .font(rowFont)

            Spacer(minLength: 16)

            Picker("", selection: $selection) {
                ForEach(PlaybackSeekInterval.allCases) { interval in
                    Text(interval.displayValue)
                        .tag(interval.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .font(rowFont)
            .tint(.secondary)
        }
        .padding(.horizontal, cardStyle ? 20 : 0)
        .padding(.vertical, cardStyle ? 0 : rowVerticalPadding)
        .frame(minHeight: cardStyle ? 58 : nil)
        .overlay(alignment: .bottom) {
            if cardStyle && showsDivider {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
                    .padding(.leading, 58)
                    .padding(.trailing, 20)
            }
        }
    }

    private var rowFont: Font {
        #if os(macOS)
        return cardStyle ? .system(size: 15) : .body
        #else
        return .body
        #endif
    }

    private var rowVerticalPadding: CGFloat {
        #if os(iOS)
        return 4
        #else
        return 2
        #endif
    }
}

#if os(macOS)
private struct SettingsCardSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: () -> Content

    init(
        title: LocalizedStringKey,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0, content: content)
                .background(Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}
