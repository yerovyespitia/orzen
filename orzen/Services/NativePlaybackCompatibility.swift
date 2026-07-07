import AVFoundation
import Foundation

enum NativePlaybackCompatibility: Sendable {
    case supported
    case likely
    case unknown
    case unsupported(String)

    var canAttemptPlayback: Bool {
        switch self {
        case .supported, .likely, .unknown:
            return true
        case .unsupported:
            return false
        }
    }

    var sortPriority: Int {
        switch self {
        case .supported:
            return 0
        case .likely:
            return 1
        case .unknown:
            return 2
        case .unsupported:
            return 3
        }
    }

    var badgeTitle: String? {
        switch self {
        case .supported:
            return nil
        case .likely:
            return nil
        case .unknown:
            return nil
        case .unsupported:
            return "Unavailable"
        }
    }

    var message: String? {
        switch self {
        case .supported:
            return nil
        case .likely:
            return "This source uses a container iOS may handle, but playback still depends on compatible video and audio codecs."
        case .unknown:
            return "Orzen cannot identify this stream format before opening it. iOS will verify it before playback."
        case .unsupported(let reason):
            return reason
        }
    }
}

enum NativePlaybackCompatibilityResolver {
    private static let validationTimeoutSeconds: UInt64 = 12

    static func compatibility(for source: StreamSource) -> NativePlaybackCompatibility {
        guard let playbackURL = source.playbackURL else {
            if source.torrentInfoHash != nil {
                return .unsupported("This source only exposes BitTorrent metadata. Orzen on iPhone needs a direct HTTP or HTTPS stream from a configured addon or debrid provider.")
            }

            return .unsupported("This source does not expose a direct video URL. iOS needs a direct HLS or MP4-style stream.")
        }

        guard ["http", "https"].contains(playbackURL.scheme?.lowercased()) else {
            return .unsupported("This source uses \(playbackURL.scheme ?? "an unsupported") links. Orzen needs a direct HTTP or HTTPS media stream.")
        }

        return .supported
    }

    static func sortedForNativePlayback(_ sources: [StreamSource]) -> [StreamSource] {
        sources.sorted { lhs, rhs in
            let lhsCompatibility = compatibility(for: lhs)
            let rhsCompatibility = compatibility(for: rhs)

            if lhsCompatibility.sortPriority != rhsCompatibility.sortPriority {
                return lhsCompatibility.sortPriority < rhsCompatibility.sortPriority
            }

            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    static func bestNativeSource(in sources: [StreamSource]) -> StreamSource? {
        sortedForNativePlayback(sources).first {
            compatibility(for: $0).canAttemptPlayback
        }
    }

    static func validatedAsset(for url: URL) async -> (asset: AVURLAsset?, errorMessage: String?) {
        let asset = AVURLAsset(url: url)

        do {
            guard let isPlayable = try await loadPlayableStatus(for: asset) else {
                return (asset, nil)
            }

            guard isPlayable else {
                return (nil, "iOS cannot play this stream directly. Try another source, or use a source that is HLS or MP4/M4V/MOV with Apple-supported codecs.")
            }

            let hasProtectedContent = (try? await asset.load(.hasProtectedContent)) ?? false
            if hasProtectedContent {
                return (nil, "This stream appears to contain protected content and cannot be played without authorization.")
            }

            return (asset, nil)
        } catch {
            return (nil, "iOS could not verify this stream before playback: \(error.localizedDescription)")
        }
    }

    private static func loadPlayableStatus(for asset: AVURLAsset) async throws -> Bool? {
        try await withThrowingTaskGroup(of: Bool?.self) { group in
            group.addTask {
                try await asset.load(.isPlayable)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: validationTimeoutSeconds * 1_000_000_000)
                return nil
            }

            guard let result = try await group.next() else {
                group.cancelAll()
                return nil
            }

            group.cancelAll()
            return result
        }
    }

    private static func compatibility(forExtension extensionHint: String) -> NativePlaybackCompatibility? {
        guard !extensionHint.isEmpty else { return nil }

        switch extensionHint {
        case "m3u8":
            return .supported
        case "mp4", "m4v", "mov", "3gp", "3g2":
            return .likely
        case "ts", "mts", "m2ts":
            return .likely
        case "mkv":
            return .unsupported("MKV is not supported by AVPlayer on iOS. Use another source or convert/remux it to HLS or MP4.")
        case "webm":
            return .unsupported("WebM is not supported by AVPlayer on iOS. Use another source or convert it to HLS or MP4.")
        case "avi", "divx", "flv", "wmv", "asf", "ogv", "ogg", "mpg", "mpeg", "vob", "rm", "rmvb":
            return .unsupported("This container is not supported by AVPlayer on iOS. Use another source or convert it to HLS or MP4.")
        case "mpd", "f4m", "ism":
            return .unsupported("MPEG-DASH (.mpd) is not supported by AVPlayer on iOS. Use an HLS (.m3u8) source instead.")
        default:
            return nil
        }
    }

    private static func compatibility(forText text: String) -> NativePlaybackCompatibility? {
        let unsupportedSignals = [
            ".mkv", " mkv", "matroska",
            ".webm", " webm",
            ".avi", " avi",
            ".divx", " divx",
            ".flv", " flv",
            ".asf", " asf",
            ".wmv", " wmv",
            ".ogv", " ogv",
            ".ogg", " ogg",
            ".vob", " vob",
            ".rmvb", " rmvb",
            ".mpd", " dash ", "mpeg-dash", "dash+xml",
            ".f4m", " hds ",
            ".ism", " smooth streaming ",
            "xvid", "msmpeg", "mpeg-2 video",
            "vp8", "vp9", "vorbis",
            "dts", "dts-hd", "truehd", "vc-1",
            "hi10p", "yuv422p", "yuv444p"
        ]

        if unsupportedSignals.contains(where: text.contains) {
            return .unsupported("This source looks like a format AVPlayer cannot open directly on iOS. Try another source or convert it to HLS or MP4.")
        }

        if text.contains(".m3u8") || text.contains(" hls ") {
            return .supported
        }

        if text.contains(".ts") || text.contains(".mts") || text.contains(".m2ts") || text.contains("mpeg-ts") || text.contains("transport stream") {
            return .likely
        }

        if text.contains(".mp4") || text.contains(".m4v") || text.contains(".mov") || text.contains(".3gp") || text.contains(".3g2") {
            return .likely
        }

        return nil
    }
}
