import Foundation

struct StreamNowPlayingMetadata: Equatable {
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    let contentID: String

    init(request: StreamPlaybackRequest) {
        title = request.title
        subtitle = request.contentType == .series ? request.subtitle : nil
        artworkURL = request.episode?.thumbnailURL
            ?? request.item?.backgroundURL
            ?? request.item?.posterURL
        contentID = request.contentID
    }
}

#if os(iOS)
import Combine
import MediaPlayer
import UIKit

@MainActor
final class IOSNowPlayingController: ObservableObject {
    private let commandCenter: MPRemoteCommandCenter
    private let infoCenter: MPNowPlayingInfoCenter
    private var commandTargets: [(command: MPRemoteCommand, target: Any)] = []
    private var artworkTask: Task<Void, Never>?
    private var sessionID = UUID()

    private var onPlay: (() -> Void)?
    private var onPause: (() -> Void)?
    private var onTogglePlayPause: (() -> Void)?
    private var onSeek: ((Double) -> Void)?
    private var onSkip: ((Double) -> Void)?

    init(
        commandCenter: MPRemoteCommandCenter = .shared(),
        infoCenter: MPNowPlayingInfoCenter = .default()
    ) {
        self.commandCenter = commandCenter
        self.infoCenter = infoCenter
    }

    deinit {
        artworkTask?.cancel()
    }

    func begin(
        metadata: StreamNowPlayingMetadata,
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onTogglePlayPause: @escaping () -> Void,
        onSeek: @escaping (Double) -> Void,
        onSkip: @escaping (Double) -> Void
    ) {
        end()

        self.onPlay = onPlay
        self.onPause = onPause
        self.onTogglePlayPause = onTogglePlayPause
        self.onSeek = onSeek
        self.onSkip = onSkip

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: metadata.title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyExternalContentIdentifier: metadata.contentID,
            MPNowPlayingInfoPropertyIsLiveStream: false,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0,
            MPNowPlayingInfoPropertyPlaybackRate: 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1
        ]

        if let subtitle = metadata.subtitle {
            nowPlayingInfo[MPMediaItemPropertyArtist] = subtitle
        }

        infoCenter.nowPlayingInfo = nowPlayingInfo
        infoCenter.playbackState = .paused
        installRemoteCommands()
        loadArtwork(from: metadata.artworkURL)
    }

    func updatePlayback(currentTime: Double, duration: Double, isPaused: Bool) {
        guard var nowPlayingInfo = infoCenter.nowPlayingInfo else { return }

        if currentTime.isFinite {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(currentTime, 0)
        }

        if duration.isFinite, duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        } else {
            nowPlayingInfo.removeValue(forKey: MPMediaItemPropertyPlaybackDuration)
        }

        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPaused ? 0 : 1
        infoCenter.nowPlayingInfo = nowPlayingInfo
        infoCenter.playbackState = isPaused ? .paused : .playing
    }

    func end() {
        sessionID = UUID()
        artworkTask?.cancel()
        artworkTask = nil

        commandTargets.forEach { registration in
            registration.command.removeTarget(registration.target)
        }
        commandTargets.removeAll()

        commandCenter.playCommand.isEnabled = false
        commandCenter.pauseCommand.isEnabled = false
        commandCenter.togglePlayPauseCommand.isEnabled = false
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false

        onPlay = nil
        onPause = nil
        onTogglePlayPause = nil
        onSeek = nil
        onSkip = nil

        infoCenter.playbackState = .stopped
        infoCenter.nowPlayingInfo = nil
    }

    private func installRemoteCommands() {
        register(commandCenter.playCommand) { [weak self] _ in
            self?.onPlay?()
            return .success
        }
        register(commandCenter.pauseCommand) { [weak self] _ in
            self?.onPause?()
            return .success
        }
        register(commandCenter.togglePlayPauseCommand) { [weak self] _ in
            self?.onTogglePlayPause?()
            return .success
        }

        commandCenter.skipForwardCommand.preferredIntervals = [10]
        register(commandCenter.skipForwardCommand) { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
            self?.onSkip?(interval)
            return .success
        }

        commandCenter.skipBackwardCommand.preferredIntervals = [10]
        register(commandCenter.skipBackwardCommand) { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
            self?.onSkip?(-interval)
            return .success
        }

        register(commandCenter.changePlaybackPositionCommand) { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.onSeek?(event.positionTime)
            return .success
        }
    }

    private func register(
        _ command: MPRemoteCommand,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        command.isEnabled = true
        let target = command.addTarget(handler: handler)
        commandTargets.append((command, target))
    }

    private func loadArtwork(from url: URL?) {
        guard let url else { return }

        let requestedSessionID = sessionID
        artworkTask = Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled,
                  let image = UIImage(data: data),
                  requestedSessionID == sessionID,
                  var nowPlayingInfo = infoCenter.nowPlayingInfo else {
                return
            }

            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
                boundsSize: image.size
            ) { _ in
                image
            }
            infoCenter.nowPlayingInfo = nowPlayingInfo
        }
    }
}
#endif
