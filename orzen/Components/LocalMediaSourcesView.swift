import SwiftUI

struct LocalMediaSourcesView: View {
    let item: CatalogItem
    let episode: CatalogEpisode?
    let play: (StreamSource) -> Void

    #if os(macOS)
    @ObservedObject private var library = LocalMediaLibraryStore.shared
    #endif
    @State private var remoteVersions: [LocalMediaVersion] = []
    @State private var searchRevision = 0
    @State private var handledSearchRevision = 0
    @State private var results: [TorrentSearchResult] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var searchError: String?
    @State private var actionError: String?
    @State private var workingIDs: Set<String> = []
    @State private var versionPendingDeletion: LocalMediaVersion?

    init(item: CatalogItem, episode: CatalogEpisode?, play: @escaping (StreamSource) -> Void) {
        self.item = item
        self.episode = episode
        self.play = play
    }

    private var versions: [LocalMediaVersion] {
        #if os(macOS)
        let all = library.versions
        #else
        let all = remoteVersions
        #endif
        return all.filter { $0.catalogID == item.id && $0.episodeID == episode?.id }
    }

    private var availableResults: [TorrentSearchResult] {
        results.filter { result in
            !versions.contains { version in
                guard version.status != .failed else { return false }
                if let hash = result.infoHash, !hash.isEmpty, !version.infoHash.isEmpty {
                    return version.infoHash.caseInsensitiveCompare(hash) == .orderedSame
                }
                return version.torrentTitle.caseInsensitiveCompare(result.title) == .orderedSame
            }
        }
    }

    private var searchRequest: SearchRequest {
        SearchRequest(contentID: episode?.id ?? item.id, revision: searchRevision)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !versions.isEmpty { downloadedVersions }
            torrentSearch
            if let actionError {
                Text(actionError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .task(id: searchRequest) {
            await search(request: searchRequest)
        }
        .alert("Delete local version?", isPresented: Binding(
            get: { versionPendingDeletion != nil },
            set: { if !$0 { versionPendingDeletion = nil } }
        )) {
            Button("Cancel", role: .cancel) { versionPendingDeletion = nil }
            Button("Delete", role: .destructive) {
                guard let version = versionPendingDeletion else { return }
                versionPendingDeletion = nil
                perform("delete", version: version)
            }
        } message: {
            Text("This will remove \(versionPendingDeletion?.torrentTitle ?? "this version") from ~/Documents/Orzen. Are you sure?")
        }
        #if os(iOS)
        .task(id: episode?.id ?? item.id) {
            while !Task.isCancelled {
                await refreshVersions()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        #endif
    }

    private var downloadedVersions: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            Text("Local versions")
                .font(.headline)
                .foregroundStyle(.white)

            ForEach(versions) { version in
                versionRow(version)
            }
            #if os(macOS)
            if let error = library.storageError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            #endif
        }
    }

    private func versionRow(_ version: LocalMediaVersion) -> some View {
        let status = version.status
        let progress = version.progress ?? 0
        let progressLabel = progress > 0 && progress < 0.01 ? "<1%" : "\(Int(progress * 100))%"
        let actionLabel: String? = switch status {
        case .completed: "Play"
        case .queued, .downloading: "Pause"
        case .paused: "Resume"
        case .failed: nil
        }
        let symbol = switch status {
        case .completed: "play.circle.fill"
        case .queued, .downloading: "pause.circle.fill"
        case .paused: "play.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
        return LocalMediaSourceCard(
            title: version.torrentTitle,
            metadata: [version.quality, status.rawValue.capitalized].compactMap { $0 }.joined(separator: " • "),
            artworkURL: item.backgroundURL,
            systemImage: symbol,
            actionLabel: actionLabel,
            isEnabled: !workingIDs.contains(version.id.uuidString),
            onSelect: actionLabel == nil ? nil : { versionPrimaryAction(version) }
        ) {
            let inferred = LocalMediaTrackLanguages.infer(from: version.torrentTitle)
            LocalMediaTrackBadges(
                audio: version.audioLanguages ?? inferred.audio,
                subtitles: version.subtitleLanguages ?? inferred.subtitles,
                verified: version.trackInfoVerified == true,
                audioCount: version.audioTrackCount,
                subtitleCount: version.subtitleTrackCount
            )
            if status == .downloading || status == .queued || status == .paused {
                if let totalBytes = version.totalBytes, totalBytes > 0 {
                    ProgressView(value: version.progress ?? 0)
                        .tint(.white)
                    Text("\(progressLabel) • \(ByteCountFormatter.string(fromByteCount: version.downloadedBytes ?? 0, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))")
                        .font(.caption).foregroundStyle(.white.opacity(0.62))
                } else {
                    Text("Waiting for torrent metadata…")
                        .font(.caption).foregroundStyle(.white.opacity(0.62))
                }
            }
            if let failure = version.failureMessage, status == .failed {
                Text(failure).font(.caption).foregroundStyle(.red)
            }
        } actions: {
            Button { versionPendingDeletion = version } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1), in: Circle())
            }
                .buttonStyle(.plain)
                .disabled(workingIDs.contains(version.id.uuidString))
                .accessibilityLabel("Delete \(version.torrentTitle)")
                .help("Delete local version")
        }
    }

    private var torrentSearch: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            HStack(spacing: 12) {
                Text("Available torrents").font(.headline).foregroundStyle(.white)
                if isSearching { ProgressView().controlSize(.small) }
                Spacer(minLength: 8)
                Button { searchRevision += 1 } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Refresh torrents")
            }
            if hasSearched && !isSearching && results.isEmpty && searchError == nil {
                Text("No torrents found for this title yet.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if !availableResults.isEmpty {
                LazyVStack(spacing: rowSpacing) {
                    ForEach(availableResults) { result in torrentRow(result) }
                }
            } else if hasSearched && !results.isEmpty {
                Text("All found versions are already in your local library.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let searchError {
                Text(searchError).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func torrentRow(_ result: TorrentSearchResult) -> some View {
        let inferred = result.inferredTracks
        let details = [result.qualityLabel,
            result.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) },
            result.seeders.map { "\($0) seeds" }].compactMap { $0 }.joined(separator: " • ")
        let canDownload = result.downloadURL != nil && !workingIDs.contains(result.id)
        return LocalMediaSourceCard(
            title: result.title,
            metadata: details,
            artworkURL: item.backgroundURL,
            systemImage: "arrow.down.circle.fill",
            actionLabel: "Download",
            isEnabled: canDownload,
            onSelect: { download(result) }
        ) {
            LocalMediaTrackBadges(audio: inferred.audio, subtitles: inferred.subtitles,
                verified: false, audioCount: nil, subtitleCount: nil)
        } actions: {
            EmptyView()
        }
    }

    private func search(request: SearchRequest) async {
        let forceRefresh = request.revision > handledSearchRevision
        handledSearchRevision = max(handledSearchRevision, request.revision)
        isSearching = true
        searchError = nil
        do {
            #if os(macOS)
            let found = try await LocalTorrentSearchClient.search(item: item, episode: episode,
                includeSpanish: true, forceRefresh: forceRefresh)
            #else
            let found = try await RemoteLocalMediaClient.shared.search(item: item, episode: episode,
                includeSpanish: true, forceRefresh: forceRefresh)
            #endif
            guard !Task.isCancelled else { return }
            results = found
        } catch {
            guard !Task.isCancelled else { return }
            searchError = error.localizedDescription
        }
        isSearching = false
        hasSearched = true
    }

    private func download(_ result: TorrentSearchResult) {
        guard !workingIDs.contains(result.id) else { return }
        workingIDs.insert(result.id)
        actionError = nil
        Task {
            do {
                #if os(macOS)
                _ = try await LocalMediaDownloadManager.shared.start(item: item, episode: episode, result: result)
                #else
                _ = try await RemoteLocalMediaClient.shared.download(item: item, episode: episode, result: result)
                await refreshVersions()
                #endif
            } catch { actionError = error.localizedDescription }
            workingIDs.remove(result.id)
        }
    }

    private func versionPrimaryAction(_ version: LocalMediaVersion) {
        switch version.status {
        case .completed: playVersion(version)
        case .queued, .downloading: perform("pause", version: version)
        case .paused: perform("resume", version: version)
        case .failed: break
        }
    }

    private var rowSpacing: CGFloat {
        #if os(iOS)
        8
        #else
        12
        #endif
    }

    private func perform(_ action: String, version: LocalMediaVersion) {
        workingIDs.insert(version.id.uuidString)
        actionError = nil
        Task {
            do {
                #if os(macOS)
                switch action {
                case "pause": try LocalMediaDownloadManager.shared.pause(version.id)
                case "resume": try LocalMediaDownloadManager.shared.resume(version.id)
                default: try LocalMediaDownloadManager.shared.delete(version.id)
                }
                #else
                try await RemoteLocalMediaClient.shared.action(action, id: version.id)
                await refreshVersions()
                #endif
            } catch { actionError = error.localizedDescription }
            workingIDs.remove(version.id.uuidString)
        }
    }

    private func playVersion(_ version: LocalMediaVersion) {
        #if os(macOS)
        let url = LocalMediaServer.shared.mediaURL(for: version)
        #else
        let url = RemoteLocalMediaClient.shared.mediaURL(for: version)
        #endif
        guard let url else { actionError = LocalMediaError.macUnavailable.localizedDescription; return }
        play(StreamSource(id: "local:\(version.id.uuidString)", addonName: "Local Media",
            title: version.torrentTitle, description: "Downloaded on Mac",
            metadata: [version.quality].compactMap { $0 },
            sourceCategory: .general, playbackURL: url))
    }

    #if os(iOS)
    private func refreshVersions() async {
        do { remoteVersions = try await RemoteLocalMediaClient.shared.versions() }
        catch { actionError = error.localizedDescription }
    }
    #endif
}

private struct SearchRequest: Hashable {
    let contentID: String
    let revision: Int
}

private struct LocalMediaSourceCard<Details: View, Actions: View>: View {
    let title: String
    let metadata: String
    let artworkURL: URL?
    let systemImage: String
    let actionLabel: String?
    let isEnabled: Bool
    let onSelect: (() -> Void)?
    @ViewBuilder let details: () -> Details
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        Group {
        #if os(iOS)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: rowSpacing) {
                    if let onSelect {
                        Button(action: onSelect) { headerContent }
                            .buttonStyle(.plain)
                            .disabled(!isEnabled)
                            .accessibilityLabel("\(actionLabel ?? "Open"), \(title)")
                    } else {
                        headerContent
                    }
                    actions()
                }

                if let onSelect {
                    details()
                        .contentShape(Rectangle())
                        .onTapGesture { if isEnabled { onSelect() } }
                } else {
                    details()
                }
            }
        #else
            HStack(alignment: .top, spacing: rowSpacing) {
                primaryContent
                actions()
            }
        #endif
        }
        .padding(rowPadding)
        .frame(minHeight: minimumHeight, alignment: .top)
        .sourceRowBackground()
    }

    @ViewBuilder
    private var primaryContent: some View {
        if let onSelect {
            Button(action: onSelect) { mainContent }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .accessibilityLabel("\(actionLabel ?? "Open"), \(title)")
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        HStack(alignment: .top, spacing: rowSpacing) {
            artwork
            VStack(alignment: .leading, spacing: 8) {
                heading
                details()
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var headerContent: some View {
        HStack(alignment: .top, spacing: rowSpacing) {
            artwork
            heading
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var artwork: some View {
        ZStack {
            if let artworkURL {
                CachedRemoteImage(url: artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: { _ in
                    OrzenArtworkPlaceholder(style: .backdrop)
                }
            } else {
                OrzenArtworkPlaceholder(style: .backdrop)
            }

            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(width: artworkWidth, height: artworkHeight)
        .clipShape(SourceRowStyle.cardShape)
        .overlay {
            SourceRowStyle.cardShape
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(titleFont)
                .foregroundStyle(.white)
                .lineLimit(2)

            if !metadata.isEmpty {
                Text(metadata)
                    .font(metadataFont)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
        }
    }

    private var artworkWidth: CGFloat {
        #if os(iOS)
        58
        #else
        190
        #endif
    }

    private var artworkHeight: CGFloat {
        #if os(iOS)
        58
        #else
        123
        #endif
    }

    private var iconSize: CGFloat {
        #if os(iOS)
        22
        #else
        28
        #endif
    }

    private var rowSpacing: CGFloat {
        #if os(iOS)
        10
        #else
        16
        #endif
    }

    private var rowPadding: CGFloat {
        #if os(iOS)
        10
        #else
        12
        #endif
    }

    private var minimumHeight: CGFloat {
        #if os(iOS)
        78
        #else
        147
        #endif
    }

    private var titleFont: Font {
        #if os(iOS)
        .subheadline.weight(.semibold)
        #else
        .headline
        #endif
    }

    private var metadataFont: Font {
        #if os(iOS)
        .caption2
        #else
        .caption
        #endif
    }
}

private struct LocalMediaTrackBadges: View {
    let audio: [String]
    let subtitles: [String]
    let verified: Bool
    let audioCount: Int?
    let subtitleCount: Int?

    var body: some View {
        #if os(iOS)
        if !audio.isEmpty || !subtitles.isEmpty || (verified && subtitleCount == 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(audio, id: \.self) { badge("Audio \($0)") }
                    ForEach(subtitles, id: \.self) { badge("Subs \($0)") }
                    if verified && subtitles.isEmpty && subtitleCount == 0 {
                        badge("Subs None")
                    }
                }
            }
        }
        #else
        HStack(spacing: 6) {
            badge("Audio", languages: audio, count: audioCount)
            badge("Subs", languages: subtitles, count: subtitleCount)
        }
        #endif
    }

    #if os(iOS)
    private func badge(_ value: String) -> some View {
        Text(value)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .font(.caption2.weight(.medium))
            .foregroundStyle(verified ? Color.white.opacity(0.82) : Color.white.opacity(0.60))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(verified ? 0.12 : 0.07), in: Capsule())
            .help(verified ? "Read from the video file" : "Estimated from the torrent title")
    }
    #else
    @ViewBuilder
    private func badge(_ label: String, languages: [String], count: Int?) -> some View {
        if let value = badgeValue(languages: languages, count: count) {
            Text("\(label) \(value)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(verified ? Color.white.opacity(0.82) : Color.white.opacity(0.60))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(verified ? 0.12 : 0.07), in: Capsule())
                .help(verified ? "Read from the video file" : "Estimated from the torrent title")
        }
    }

    private func badgeValue(languages: [String], count: Int?) -> String? {
        if !languages.isEmpty { return languages.joined(separator: " · ") }
        if verified && count == 0 { return "None" }
        return nil
    }
    #endif
}
