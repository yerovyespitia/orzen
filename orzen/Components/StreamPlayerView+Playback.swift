import AVFoundation

extension StreamPlayerView {
    func startPlaybackIfPossible() {
        guard player == nil, !isPreparingNativePlayback else { return }

        #if os(iOS)
        let decision = StreamPlayerPlaybackPolicy.initialDecision(
            for: request.source,
            platform: .iOS,
            isVLCAvailable: vlcController.isAvailable
        )
        #else
        let decision = StreamPlayerPlaybackPolicy.initialDecision(
            for: request.source,
            platform: .macOS,
            isVLCAvailable: false
        )
        #endif

        switch decision {
        case .failure(let message):
            playbackObserver.errorMessage = message
        case .play(_, with: .mpv):
            activePlaybackEngine = .mpv
            playbackObserver.stop()
            playbackObserver.errorMessage = nil
        case .play(let playbackURL, with: .vlc):
            #if os(iOS)
            IOSMediaPlaybackSession.activate()
            startVLCPlayback(with: playbackURL)
            #endif
        case .play(let playbackURL, with: .native):
            #if os(iOS)
            IOSMediaPlaybackSession.activate()
            #endif
            startNativePlayback(with: playbackURL)
        }
    }

    #if os(iOS)
    func startVLCPlayback(with playbackURL: URL) {
        guard vlcController.isAvailable else {
            startNativePlayback(with: playbackURL)
            return
        }

        activePlaybackEngine = .vlc
        playbackObserver.stop()
        playbackObserver.errorMessage = nil
        vlcController.play(url: playbackURL)
    }
    #endif

    func startNativeFallbackIfPossible() {
        #if os(macOS)
        guard activePlaybackEngine == .mpv,
              let playbackURL = request.source.playbackURL,
              player == nil else { return }

        mpvController.clearError()
        startNativePlayback(with: playbackURL)
        #endif
    }

    func startNativePlayback(with playbackURL: URL) {
        isPreparingNativePlayback = true
        playbackObserver.errorMessage = nil

        Task {
            let result = await NativePlaybackCompatibilityResolver.validatedAsset(for: playbackURL)

            await MainActor.run {
                isPreparingNativePlayback = false
                guard !isClosing, player == nil else { return }

                if let asset = result.asset {
                    startNativePlayback(with: asset)
                } else {
                    handleNativeValidationFailure(
                        result.errorMessage ?? "iOS could not verify this stream before playback."
                    )
                }
            }
        }
    }

    func handleNativeValidationFailure(_ message: String) {
        #if os(iOS)
        if let playbackURL = request.source.playbackURL, vlcController.isAvailable {
            startVLCPlayback(with: playbackURL)
        } else {
            activePlaybackEngine = .native
            playbackObserver.errorMessage = message
            chromeVisibility.keepVisible()
        }
        #else
        activePlaybackEngine = .native
        playbackObserver.errorMessage = message
        chromeVisibility.keepVisible()
        #endif
    }

    func startNativeFallbackAfterRuntimeErrorIfPossible() {
        #if os(iOS)
        if vlcController.errorMessage?.contains("audio cannot be decoded") == true {
            return
        }

        guard !isPreparingNativePlayback,
              !isResolvingNativeFallback,
              activePlaybackEngine == .vlc || (activePlaybackEngine == .native && player != nil) else {
            return
        }

        isResolvingNativeFallback = true

        Task {
            let fallbackRequest = await fallbackPlaybackRequestAfterNativeFailure()

            await MainActor.run {
                isResolvingNativeFallback = false
                guard !isClosing, let fallbackRequest else { return }

                stopCurrentIOSPlaybackForFallback()
                StreamPlaybackStore.shared.request = fallbackRequest
            }
        }
        #endif
    }

    #if os(iOS)
    func stopCurrentIOSPlaybackForFallback() {
        vlcController.stop()
        player?.pause()
        removeNativeTimeObserver()
        playbackObserver.stop()
        cancelNativeStartupTimeout()
        player = nil
    }
    #endif

    func fallbackPlaybackRequestAfterNativeFailure() async -> StreamPlaybackRequest? {
        #if os(iOS)
        let sources = await StreamSourceResolver.fetchAllSources(
            from: addonStore.streamAddons,
            type: request.contentType,
            id: request.contentID
        )
        guard let selection = StreamPlayerPlaybackPolicy.fallbackSelection(
            currentSource: request.source,
            previouslyAttemptedSourceIDs: request.attemptedSourceIDs,
            candidates: sources
        ) else {
            return nil
        }

        return StreamPlaybackRequest(
            source: selection.source,
            title: request.title,
            subtitle: request.subtitle,
            contentID: request.contentID,
            contentType: request.contentType,
            item: request.item,
            episode: request.episode,
            initialTrackSelections: request.initialTrackSelections,
            attemptedSourceIDs: selection.attemptedSourceIDs
        )
        #else
        return nil
        #endif
    }

    func startNativePlayback(with asset: AVURLAsset) {
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        activePlaybackEngine = .native
        self.player = player
        nativeIsPaused = false
        nativeVolume = Double(player.volume * 100)
        nativeIsMuted = player.isMuted
        playbackObserver.observe(playerItem: item)
        installNativeTimeObserver(player)
        refreshNativeMediaTracks()
        player.play()
        scheduleNativeStartupTimeout()
    }


    func installNativeTimeObserver(_ player: AVPlayer) {
        removeNativeTimeObserver()
        nativeTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.4, preferredTimescale: 600),
            queue: .main
        ) { [weak player] time in
            Task { @MainActor in
                nativeTime = time.seconds.isFinite ? time.seconds : 0
                let duration = player?.currentItem?.duration.seconds ?? 0
                nativeDuration = duration.isFinite ? duration : 0
                nativeIsPaused = player?.timeControlStatus != .playing
                nativeVolume = Double((player?.volume ?? 1) * 100)
                nativeIsMuted = player?.isMuted ?? false
                if nativeTime > nativeStartupMinimumProgress {
                    cancelNativeStartupTimeout()
                }
                refreshNativeMediaTracks()
            }
        }
    }

    func removeNativeTimeObserver() {
        if let nativeTimeObserver {
            player?.removeTimeObserver(nativeTimeObserver)
            self.nativeTimeObserver = nil
        }
    }

    func scheduleNativeStartupTimeout() {
        #if os(iOS)
        cancelNativeStartupTimeout()
        let timeoutWorkItem = DispatchWorkItem {
            handleNativeStartupTimeoutIfNeeded()
        }
        nativeStartupTimeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeoutWorkItem)
        #endif
    }

    func cancelNativeStartupTimeout() {
        nativeStartupTimeoutWorkItem?.cancel()
        nativeStartupTimeoutWorkItem = nil
    }

    func handleNativeStartupTimeoutIfNeeded() {
        #if os(iOS)
        guard activePlaybackEngine == .native,
              player != nil,
              nativeTime <= nativeStartupMinimumProgress,
              !isResolvingNativeFallback else {
            return
        }

        isResolvingNativeFallback = true

        Task {
            let fallbackRequest = await fallbackPlaybackRequestAfterNativeFailure()

            await MainActor.run {
                isResolvingNativeFallback = false

                player?.pause()
                removeNativeTimeObserver()
                playbackObserver.stop()
                cancelNativeStartupTimeout()

                if let fallbackRequest {
                    player = nil
                    StreamPlaybackStore.shared.request = fallbackRequest
                } else {
                    activePlaybackEngine = .native
                    playbackObserver.errorMessage = "This stream did not start in time. It may use codecs, headers, or a server response that AVPlayer on iOS cannot handle reliably."
                    chromeVisibility.keepVisible()
                }
            }
        }
        #endif
    }
}
