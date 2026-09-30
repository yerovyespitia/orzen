import SwiftUI

struct SettingsView: View {
    @AppStorage(LocalMediaModePreference.storageKey)
    private var localMediaModeEnabled = false
    @ObservedObject private var torznabSettings = TorznabSettingsStore.shared
    #if os(macOS)
    @ObservedObject private var localServer = LocalMediaServer.shared
    #else
    @ObservedObject private var remoteMedia = RemoteLocalMediaClient.shared
    #endif

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
        Group {
            #if os(macOS)
            macSettings
            #else
            iPhoneSettings
            #endif
        }
        .onAppear {
            #if os(macOS)
            if localMediaModeEnabled { localServer.start() }
            #endif
        }
        .onChange(of: localMediaModeEnabled) { _, enabled in
            #if os(macOS)
            if enabled { localServer.start() } else { localServer.stop() }
            #endif
        }
    }

    #if os(macOS)
    private var macSettings: some View {
        NavigationStack {
            OrzenScreen(title: "Settings") {
                OrzenScreenScrollView {
                    VStack(alignment: .leading, spacing: 24) {
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
                                cardStyle: true,
                                showsDivider: true
                            )

                            SettingsToggleRow(
                                title: "Local Media",
                                systemImage: "externaldrive",
                                isOn: $localMediaModeEnabled,
                                cardStyle: true
                            )
                        }

                        if localMediaModeEnabled {
                            SettingsCardSection(title: "Local Media") {
                                NavigationLink {
                                    macLibraryDetails
                                } label: {
                                    SettingsRow(
                                        title: "Mac Library",
                                        systemImage: "externaldrive",
                                        cardStyle: true,
                                        showsDivider: true,
                                        showsChevron: true
                                    )
                                }
                                .buttonStyle(.plain)

                                NavigationLink {
                                    torrentSearchDetails
                                } label: {
                                    SettingsRow(
                                        title: "Torrent Search",
                                        systemImage: "magnifyingglass",
                                        cardStyle: true,
                                        showsChevron: true
                                    )
                                }
                                .buttonStyle(.plain)
                            }
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
                }
            }
            .navigationTitle("Settings")
        }
        .background(Color.black)
    }

    private var macLibraryDetails: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Mac Library")
                    .font(.largeTitle.bold())

                SettingsCardSection(title: "Library") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Files: ~/Documents/Orzen")
                        Text("Connect iPhone to \(localServer.hostName):8937")
                        Text("Pairing code: \(localServer.pairingCode)")
                        Text(localServer.isRunning ? "Sharing on local network" : (localServer.errorMessage ?? "Starting local server"))
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .background(Color.black)
        .navigationTitle("Mac Library")
    }

    private var torrentSearchDetails: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Torrent Search")
                    .font(.largeTitle.bold())

                SettingsCardSection(title: "Search") {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Automatic search is ready. Titles are searched when you open a movie or episode.")
                            .foregroundStyle(.secondary)
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 1)
                        torznabConfiguration
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .background(Color.black)
        .navigationTitle("Torrent Search")
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

                    SettingsToggleRow(
                        title: "Local Media",
                        systemImage: "externaldrive",
                        isOn: $localMediaModeEnabled
                    )
                }

                if localMediaModeEnabled {
                    Section("Local Media") {
                        NavigationLink {
                            iPhoneLibraryDetails
                        } label: {
                            SettingsRow(title: "Mac Library", systemImage: "externaldrive")
                        }
                    }
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

    private var iPhoneLibraryDetails: some View {
        List {
            Section("Mac Library") {
                if remoteMedia.isPaired {
                    Label("Paired with Mac", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(remoteMedia.host)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Button("Disconnect from Mac", role: .destructive) {
                        remoteMedia.disconnect()
                    }
                } else {
                    TextField("Mac name or IP address", text: $remoteMedia.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Pairing code", text: $remoteMedia.pairingCode)
                        .keyboardType(.numberPad)
                    Button("Connect to Mac") { Task { await remoteMedia.pair() } }
                    if let message = remoteMedia.message {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle("Mac Library")
    }
    #endif

    private var torznabConfiguration: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Optional Torznab provider")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Text("Only needed if you also use Prowlarr or Jackett. Paste its Torznab API URL (ending in /api) and API key.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Torznab API URL", text: $torznabSettings.endpointText)
                .modifier(SettingsTextInputStyle())

            SecureField("API key", text: $torznabSettings.apiKey)
                .modifier(SettingsTextInputStyle())

            HStack {
                Spacer()
                Button {
                    torznabSettings.save()
                } label: {
                    Text("Save Search Provider")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.black.opacity(0.86))
                        .padding(.horizontal, 22)
                        .frame(height: 46)
                        .background(Color.white.opacity(0.9), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if let saveMessage = torznabSettings.saveMessage {
                Text(saveMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingsTextInputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundStyle(.white)
            .tint(.white)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
    }
}

private struct SettingsToggleRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    @Binding var isOn: Bool
    var cardStyle = false

    var body: some View {
        HStack(spacing: 12) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(.blue)
            }
            .font(cardStyle ? .system(size: 15) : .body)

            Spacer(minLength: 16)

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.blue)
                .fixedSize()
        }
        .padding(.horizontal, cardStyle ? 20 : 0)
        .padding(.vertical, cardStyle ? 0 : 4)
        .frame(minHeight: cardStyle ? 58 : nil)
    }
}

private struct SettingsRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    var value: String?
    var cardStyle = false
    var showsDivider = false
    var showsChevron = false

    init(
        title: LocalizedStringKey,
        systemImage: String,
        value: String? = nil,
        cardStyle: Bool = false,
        showsDivider: Bool = false,
        showsChevron: Bool = false
    ) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.cardStyle = cardStyle
        self.showsDivider = showsDivider
        self.showsChevron = showsChevron
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
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, cardStyle ? 20 : 0)
        .padding(.vertical, cardStyle ? 0 : rowVerticalPadding)
        .frame(minHeight: cardStyle ? 58 : nil)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
