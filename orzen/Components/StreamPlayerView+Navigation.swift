import SwiftUI

extension StreamPlayerView {
    func scheduleChromeHideIfNeeded() {
        chromeVisibility.scheduleAutoHide(isAllowed: shouldAutoHideChrome)
    }

    func handleTimelineInteractionChange(_ isInteracting: Bool) {
        isAdjustingTimeline = isInteracting

        if isInteracting {
            chromeVisibility.keepVisible()
        } else {
            scheduleChromeHideIfNeeded()
        }
    }

    func handlePlayerTap() {
        guard playbackErrorMessage == nil, !isEpisodeSidebarPresented, !isAdjustingTimeline else {
            chromeVisibility.keepVisible()
            return
        }

        if chromeVisibility.isVisible {
            chromeVisibility.hide()
        } else {
            chromeVisibility.reveal()
            if shouldAutoHideChrome {
                scheduleChromeHideIfNeeded()
            }
        }
    }

    func performPlayerAction(_ action: () -> Void) {
        guard !isClosing else { return }
        chromeVisibility.reveal()
        action()
        scheduleChromeHideIfNeeded()
    }

    func handleBack() {
        guard !isClosing else { return }
        if exitFullscreenIfNeeded() {
            shouldBackAfterFullscreenExit = true
            return
        }

        closePlayer()
    }

    func handleEscape() {
        guard !isClosing else { return }
        if isEpisodeSidebarPresented {
            closeEpisodeSidebar()
            return
        }

        guard !exitFullscreenIfNeeded() else { return }

        closePlayer()
    }

    func completePendingBackAfterFullscreenExit() {
        guard shouldBackAfterFullscreenExit else { return }
        shouldBackAfterFullscreenExit = false
        closePlayer()
    }

    func closePlayer() {
        guard !isClosing else { return }
        isClosing = true
        saveCurrentProgress(force: true)
        if duration > 0, !canCompleteCurrentPlayback {
            clearCurrentPlaybackProgress()
        }
        chromeVisibility.cancelAutoHide()
        player?.pause()
        #if os(iOS)
        if activePlaybackEngine == .vlc {
            vlcController.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                onBack()
            }
            return
        }
        #endif
        mpvController.pause()
        onBack()
    }

    func showEpisodeSidebar() {
        guard canShowEpisodeSidebar else { return }

        performPlayerAction {
            guard !isEpisodeSidebarPresented else { return }
            isEpisodeSidebarPresented = true
            chromeVisibility.keepVisible()
        }
    }

    func closeEpisodeSidebar() {
        guard isEpisodeSidebarPresented else { return }

        performPlayerAction {
            isEpisodeSidebarPresented = false
        }
    }


    func toggleFullscreen() {
        #if os(macOS)
        performPlayerAction {
            NSApp.keyWindow?.toggleFullScreen(nil)
        }
        #else
        performPlayerAction {
            isFullscreen.toggle()
        }
        #endif
    }

    func exitFullscreenIfNeeded() -> Bool {
        #if os(macOS)
        guard let window = NSApp.keyWindow,
              window.styleMask.contains(.fullScreen) else { return false }

        chromeVisibility.reveal()
        window.toggleFullScreen(nil)
        return true
        #else
        return false
        #endif
    }

    func refreshFullscreenState() {
        #if os(macOS)
        isFullscreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) == true
        #else
        isFullscreen = true
        #endif
    }
}
