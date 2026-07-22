import AVFoundation

extension StreamPlayerView {
    func togglePlayPause() {
        performPlayerAction {
            switch activePlaybackEngine {
            case .mpv:
                mpvController.togglePlayPause()
            case .vlc:
                #if os(iOS)
                vlcController.togglePlayPause()
                #endif
            case .native:
                guard let player else { return }
                if player.timeControlStatus == .playing {
                    player.pause()
                    nativeIsPaused = true
                } else {
                    player.play()
                    nativeIsPaused = false
                }
            case nil:
                break
            }
        }
    }

    func seek(to time: Double) {
        performPlayerAction {
            switch activePlaybackEngine {
            case .mpv:
                mpvController.seek(to: time)
            case .vlc:
                #if os(iOS)
                vlcController.seek(to: time)
                #endif
            case .native:
                let target = CMTime(seconds: time, preferredTimescale: 600)
                player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                nativeTime = time
            case nil:
                break
            }
        }
    }

    func seek(by offset: Double) {
        performPlayerAction {
            switch activePlaybackEngine {
            case .mpv:
                mpvController.seek(by: offset)
            case .vlc:
                #if os(iOS)
                vlcController.seek(by: offset)
                #endif
            case .native:
                let targetTime = min(max(nativeTime + offset, 0), max(nativeDuration, 0))
                seek(to: targetTime)
            case nil:
                break
            }
        }
    }

    func setVolume(_ value: Double) {
        performPlayerAction {
            let clampedValue = min(max(value, 0), 100)

            switch activePlaybackEngine {
            case .mpv:
                mpvController.setVolume(clampedValue)
            case .vlc:
                #if os(iOS)
                vlcController.setVolume(clampedValue)
                #endif
            case .native:
                player?.volume = Float(clampedValue / 100)
                player?.isMuted = clampedValue == 0
                nativeVolume = clampedValue
                nativeIsMuted = player?.isMuted ?? nativeIsMuted
            case nil:
                break
            }
        }
    }

    func toggleMute() {
        performPlayerAction {
            switch activePlaybackEngine {
            case .mpv:
                mpvController.toggleMute()
            case .vlc:
                #if os(iOS)
                vlcController.toggleMute()
                #endif
            case .native:
                guard let player else { return }
                player.isMuted.toggle()
                nativeIsMuted = player.isMuted
            case nil:
                break
            }
        }
    }
}
