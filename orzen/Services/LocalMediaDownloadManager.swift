import Foundation

#if os(macOS)
@MainActor
final class LocalMediaDownloadManager {
    static let shared = LocalMediaDownloadManager()

    private let library = LocalMediaLibraryStore.shared
    private let session: UnsafeMutableRawPointer?
    private var handles: [UUID: UnsafeMutableRawPointer] = [:]
    private var inspectionsInProgress: Set<UUID> = []
    private var inspectionAttempts: [UUID: Int] = [:]
    private var pollTask: Task<Void, Never>?

    private init() {
        session = orzen_torrent_session_create()
        for version in library.versions where version.status != .completed && version.status != .failed {
            do { try attach(version) }
            catch { markFailed(version, error: error) }
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func start(item: CatalogItem, episode: CatalogEpisode?, result: TorrentSearchResult) async throws -> LocalMediaVersion {
        guard session != nil else { throw LocalMediaError.torrentUnavailable }
        guard let url = result.downloadURL else { throw LocalMediaError.missingTorrent }
        let version = try library.reserveVersion(
            for: item, episode: episode, infoHash: result.infoHash ?? "",
            torrentTitle: result.title, language: result.languageLabel, quality: result.qualityLabel,
            audioLanguages: result.inferredTracks.audio,
            subtitleLanguages: result.inferredTracks.subtitles
        )
        var saved = version
        do {
            if url.scheme?.lowercased() == "magnet" {
                saved.magnetURI = url.absoluteString
            } else {
                var request = URLRequest(url: url)
                request.timeoutInterval = 30
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode), data.count < 20_000_000 else {
                    throw LocalMediaError.invalidTorrent
                }
                let relative = "\(saved.folderRelativePath)/source.torrent"
                try data.write(to: library.rootURL.appending(path: relative), options: .atomic)
                saved.torrentFileRelativePath = relative
            }
            try library.update(saved)
            try attach(saved)
            return saved
        } catch {
            markFailed(saved, error: error)
            throw error
        }
    }

    func pause(_ id: UUID) throws {
        guard let handle = handles[id], var version = library.versions.first(where: { $0.id == id }) else { return }
        orzen_torrent_pause(handle)
        version.status = .paused
        try library.update(version)
    }

    func resume(_ id: UUID) throws {
        guard let handle = handles[id], var version = library.versions.first(where: { $0.id == id }) else { return }
        orzen_torrent_resume(handle)
        version.status = .downloading
        try library.update(version)
    }

    func delete(_ id: UUID) throws {
        guard let version = library.versions.first(where: { $0.id == id }) else { return }
        if let handle = handles.removeValue(forKey: id) { orzen_torrent_remove(session, handle) }
        try library.remove(version)
    }

    private func attach(_ version: LocalMediaVersion) throws {
        guard let session else { throw LocalMediaError.torrentUnavailable }
        let folder = library.rootURL.appending(path: version.folderRelativePath).path
        let episodeTag = version.episodeID.flatMap(Self.episodeTag) ?? ""
        var error = [CChar](repeating: 0, count: 512)
        let handle: UnsafeMutableRawPointer? = error.withUnsafeMutableBufferPointer { buffer in
            folder.withCString { folderCString in
                episodeTag.withCString { episodeCString in
                    if let magnet = version.magnetURI {
                        return magnet.withCString {
                            orzen_torrent_add_magnet(session, $0, folderCString, episodeCString, buffer.baseAddress, 512)
                        }
                    }
                    if let path = version.torrentFileRelativePath {
                        return library.rootURL.appending(path: path).path.withCString {
                            orzen_torrent_add_file(session, $0, folderCString, episodeCString, buffer.baseAddress, 512)
                        }
                    }
                    return nil
                }
            }
        }
        guard let handle else { throw LocalMediaError.engine(String(cString: error)) }
        handles[version.id] = handle
        if version.status == .paused { orzen_torrent_pause(handle) }
    }

    private static func episodeTag(_ id: String) -> String? {
        let parts = id.split(separator: ":")
        guard parts.count >= 3, let season = Int(parts[1]), let episode = Int(parts[2]) else { return nil }
        return String(format: "S%02dE%02d", season, episode)
    }

    private func poll() {
        for (id, handle) in handles {
            guard var version = library.versions.first(where: { $0.id == id }) else { continue }
            var snapshot = OrzenTorrentSnapshot()
            orzen_torrent_poll(handle, &snapshot)
            let error = withUnsafePointer(to: &snapshot.error_message) {
                $0.withMemoryRebound(to: CChar.self, capacity: 512) { String(cString: $0) }
            }
            if !error.isEmpty {
                version.status = .failed
                version.failureMessage = error
            } else if version.status != .paused {
                version.status = snapshot.is_finished != 0 ? .completed : .downloading
            }
            if snapshot.has_metadata != 0 {
                let path = withUnsafePointer(to: &snapshot.relative_file_path) {
                    $0.withMemoryRebound(to: CChar.self, capacity: 4096) { String(cString: $0) }
                }
                if !path.isEmpty && !path.contains("..") && !path.hasPrefix("/") {
                    version.videoRelativePath = "\(version.folderRelativePath)/\(path)"
                }
                version.progress = snapshot.progress
                version.downloadedBytes = snapshot.downloaded_bytes
                version.totalBytes = snapshot.file_size
                version.downloadRate = Int(snapshot.download_rate)
            }
            try? library.update(version)
        }
        for version in library.versions where version.status == .completed && version.trackInfoVersion != 2 {
            inspectTracksIfNeeded(for: version)
        }
    }

    private func inspectTracksIfNeeded(for version: LocalMediaVersion) {
        guard !inspectionsInProgress.contains(version.id),
              inspectionAttempts[version.id, default: 0] < 3,
              let fileURL = library.fileURL(for: version),
              FileManager.default.fileExists(atPath: fileURL.path) else { return }
        inspectionsInProgress.insert(version.id)
        inspectionAttempts[version.id, default: 0] += 1
        Task { [weak self] in
            let tracks = await LocalMediaTrackInspector.inspect(fileURL)
            guard let self else { return }
            defer { inspectionsInProgress.remove(version.id) }
            guard var latest = library.versions.first(where: { $0.id == version.id }) else { return }
            if let tracks {
                latest.audioLanguages = tracks.audio
                latest.subtitleLanguages = tracks.subtitles
                latest.audioTrackCount = tracks.audioCount
                latest.subtitleTrackCount = tracks.subtitleCount
                latest.trackInfoVerified = true
                latest.trackInfoVersion = 2
            } else if latest.trackInfoVerified != true {
                latest.trackInfoVerified = false
            }
            try? library.update(latest)
        }
    }

    private func markFailed(_ version: LocalMediaVersion, error: Error) {
        var version = version
        version.status = .failed
        version.failureMessage = error.localizedDescription
        try? library.update(version)
    }
}

private struct InspectedMediaTracks: Sendable {
    let audio: [String]
    let subtitles: [String]
    let audioCount: Int
    let subtitleCount: Int
}

private enum LocalMediaTrackInspector {
    static func inspect(_ fileURL: URL) async -> InspectedMediaTracks? {
        await Task.detached(priority: .utility) {
            var snapshot = OrzenMediaTrackSnapshot()
            guard fileURL.path.withCString({ orzen_mpv_probe_tracks($0, &snapshot) }) != 0 else { return nil }
            let audio = withUnsafePointer(to: &snapshot.audio_languages) {
                $0.withMemoryRebound(to: CChar.self, capacity: 512) { String(cString: $0) }
            }
            let subtitles = withUnsafePointer(to: &snapshot.subtitle_languages) {
                $0.withMemoryRebound(to: CChar.self, capacity: 512) { String(cString: $0) }
            }
            return InspectedMediaTracks(
                audio: normalizedLanguages(audio), subtitles: normalizedLanguages(subtitles),
                audioCount: Int(snapshot.audio_track_count),
                subtitleCount: Int(snapshot.subtitle_track_count)
            )
        }.value
    }

    private static func normalizedLanguages(_ value: String) -> [String] {
        var seen = Set<String>()
        return value.split(separator: ",").compactMap { raw -> String? in
            let language = String(raw)
            let code: String?
            switch language.lowercased() {
            case "es-419": code = "ES-LAT"
            case "es-es": code = "ES-ES"
            default:
                let base = String(raw.split(separator: "-").first ?? raw)
                code = LocalMediaTrackLanguages.normalizedCode(base)
            }
            guard let code, seen.insert(code).inserted else {
                return nil
            }
            return code
        }
    }
}
#endif

enum LocalMediaError: LocalizedError {
    case torrentUnavailable, missingTorrent, invalidTorrent, engine(String), macUnavailable, unauthorized

    var errorDescription: String? {
        switch self {
        case .torrentUnavailable: "libtorrent is unavailable on this Mac."
        case .missingTorrent: "This result has no magnet or torrent download."
        case .invalidTorrent: "The torrent file could not be downloaded."
        case .engine(let message): message.isEmpty ? "Could not start the torrent." : message
        case .macUnavailable: "Orzen on your Mac isn't available. Open it and pair this iPhone in Settings to browse torrents."
        case .unauthorized: "This iPhone isn't paired with your Mac. Pair it in Settings to browse torrents."
        }
    }
}
