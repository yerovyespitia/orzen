#if os(iOS)
import Foundation
import SwiftUI

#if canImport(VLCKit)
import VLCKit

@MainActor
final class VLCPlaybackController: NSObject, ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPaused = true
    @Published var volume: Double = 100
    @Published var isMuted = false
    @Published var audioTracks: [PlayerMediaTrack] = []
    @Published var subtitleTracks: [PlayerMediaTrack] = []
    @Published var errorMessage: String?
    @Published var didReachEnd = false
    @Published var isStarting = false

    private let player = VLCMediaPlayer()
    private var timer: Timer?
    private var lastVolume: Double = 100
    private var currentMedia: VLCMedia?

    var isAvailable: Bool { true }

    override init() {
        super.init()
        player.delegate = self
    }

    deinit {
        timer?.invalidate()
        player.delegate = nil
        player.stop()
    }

    var drawable: Any? {
        get { player.drawable }
        set { player.drawable = newValue }
    }

    func play(url: URL) {
        stop()
        errorMessage = nil
        didReachEnd = false
        isStarting = true
        isPaused = false

        guard let media = VLCMedia(url: url) else {
            errorMessage = "VLC could not open this stream URL."
            isStarting = false
            return
        }

        media.addOptions([
            "network-caching": 1500,
            "http-reconnect": true,
            "codec": "any"
        ])
        currentMedia = media
        player.media = media
        player.play()
        startTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if currentMedia != nil {
            player.stop()
        }
        currentMedia = nil
        isStarting = false
        isPaused = true
        currentTime = 0
        duration = 0
        audioTracks = []
        subtitleTracks = []
    }

    func togglePlayPause() {
        if player.isPlaying {
            pause()
        } else {
            player.play()
            isPaused = false
        }
    }

    func pause() {
        player.pause()
        isPaused = true
    }

    func seek(to time: Double) {
        player.time = VLCTime(int: Int32(max(time, 0) * 1000))
        currentTime = max(time, 0)
    }

    func seek(by offset: Double) {
        let targetTime = min(max(currentTime + offset, 0), max(duration, 0))
        seek(to: targetTime)
    }

    func setVolume(_ value: Double) {
        let clampedValue = min(max(value, 0), 100)
        player.audio?.volume = Int32(clampedValue)
        volume = clampedValue
        isMuted = clampedValue == 0
        if clampedValue > 0 {
            lastVolume = clampedValue
        }
    }

    func toggleMute() {
        if isMuted {
            setVolume(lastVolume > 0 ? lastVolume : 100)
        } else {
            lastVolume = volume
            setVolume(0)
        }
    }

    func selectAudioTrack(_ track: PlayerMediaTrack) {
        guard let index = trackIndex(from: track.id) else { return }
        player.selectTrack(at: index, type: .audio)
        refreshTracks()
    }

    func selectSubtitleTrack(_ track: PlayerMediaTrack) {
        guard let index = trackIndex(from: track.id) else { return }
        player.selectTrack(at: index, type: .text)
        refreshTracks()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPlaybackState()
            }
        }
    }

    private func refreshPlaybackState() {
        currentTime = seconds(from: player.time)
        duration = seconds(from: currentMedia?.length)
        isPaused = !player.isPlaying
        volume = Double(player.audio?.volume ?? 0)
        isMuted = (player.audio?.volume ?? 0) == 0

        if currentTime > 0 || player.isPlaying {
            isStarting = false
        }

        if duration > 0, max(duration - currentTime, 0) <= 1.25, !player.isPlaying {
            didReachEnd = true
        }

        refreshTracks()
    }

    private func refreshTracks() {
        audioTracks = tracks(
            vlcTracks: player.audioTracks,
            kind: .audio,
            prefix: "vlc-audio",
            includesOffOption: false
        )
        subtitleTracks = tracks(
            vlcTracks: player.textTracks,
            kind: .subtitle,
            prefix: "vlc-subtitle",
            includesOffOption: true
        )
    }

    private func tracks(
        vlcTracks: [VLCMediaPlayer.Track],
        kind: PlayerMediaTrack.Kind,
        prefix: String,
        includesOffOption: Bool
    ) -> [PlayerMediaTrack] {
        var tracks: [PlayerMediaTrack] = []

        if includesOffOption {
            tracks.append(
                PlayerMediaTrack(
                    id: "\(prefix)--1",
                    title: "Off",
                    language: nil,
                    kind: kind,
                    isSelected: !vlcTracks.contains { $0.isSelected },
                    isOff: true
                )
            )
        }

        tracks.append(
            contentsOf: vlcTracks.enumerated().map { offset, track in
                return PlayerMediaTrack(
                    id: "\(prefix)-\(offset)",
                    title: normalizedTrackTitle(track.trackName, fallback: "\(kind.defaultTitle) \(offset + 1)"),
                    language: nil,
                    kind: kind,
                    isSelected: track.isSelected,
                    isOff: false
                )
            }
        )

        return tracks
    }

    private func normalizedTrackTitle(_ title: String?, fallback: String) -> String {
        guard let title,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        return title
    }

    private func trackIndex(from id: String) -> Int? {
        Int(id.split(separator: "-").last ?? "")
    }

    private func seconds(from time: VLCTime?) -> Double {
        guard let time else { return 0 }
        let value = Double(time.value?.doubleValue ?? 0) / 1000
        return value.isFinite && value > 0 ? value : 0
    }
}

extension VLCPlaybackController: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        Task { @MainActor in
            refreshPlaybackState()

            switch newState {
            case .error:
                errorMessage = "VLC could not play this stream."
                isStarting = false
            case .opening, .buffering:
                isStarting = true
            case .stopped:
                if duration > 0, max(duration - currentTime, 0) <= 1.25 {
                    didReachEnd = true
                }
                isPaused = true
                isStarting = false
            case .paused:
                isPaused = true
                isStarting = false
            case .playing:
                isPaused = false
                isStarting = false
            default:
                break
            }
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor in
            refreshPlaybackState()
        }
    }
}
#else
@MainActor
final class VLCPlaybackController: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPaused = true
    @Published var volume: Double = 100
    @Published var isMuted = false
    @Published var audioTracks: [PlayerMediaTrack] = []
    @Published var subtitleTracks: [PlayerMediaTrack] = []
    @Published var errorMessage: String?
    @Published var didReachEnd = false
    @Published var isStarting = false

    var drawable: Any?
    var isAvailable: Bool { false }

    func play(url: URL) {
        errorMessage = "Install the VLCKit CocoaPod to enable broad-format playback on iOS."
    }

    func stop() { }
    func togglePlayPause() { }
    func pause() { }
    func seek(to time: Double) { }
    func seek(by offset: Double) { }
    func setVolume(_ value: Double) { }
    func toggleMute() { }
    func selectAudioTrack(_ track: PlayerMediaTrack) { }
    func selectSubtitleTrack(_ track: PlayerMediaTrack) { }
}
#endif
#endif
