#if os(iOS)
import SwiftUI
import UIKit
#if canImport(VLCKit)
import VLCKit
#endif

struct VLCPlayerView: UIViewRepresentable {
    @ObservedObject var controller: VLCPlaybackController
    @ObservedObject var pictureInPictureSession: PictureInPictureSession

    func makeUIView(context: Context) -> VLCPictureInPictureView {
        let view = VLCPictureInPictureView(
            playbackController: controller,
            pictureInPictureSession: pictureInPictureSession
        )
        controller.drawable = view
        return view
    }

    func updateUIView(_ uiView: VLCPictureInPictureView, context: Context) {
        if controller.drawable == nil {
            controller.drawable = uiView
        }
        uiView.updatePlaybackState(
            currentTime: controller.currentTime,
            duration: controller.duration,
            isPaused: controller.isPaused,
            isSeekable: controller.isSeekable
        )
    }

    static func dismantleUIView(_ uiView: VLCPictureInPictureView, coordinator: ()) {
        uiView.detach()
    }
}

#if canImport(VLCKit)
final class VLCPictureInPictureView: UIView, VLCPictureInPictureDrawable {
    private let registrationID = UUID()
    private weak var playbackController: VLCPlaybackController?
    private let pictureInPictureSession: PictureInPictureSession
    private let mediaControlAdapter: VLCPictureInPictureMediaController
    private var windowController: VLCPictureInPictureWindowControlling?
    private var isPictureInPictureActive = false

    init(
        playbackController: VLCPlaybackController,
        pictureInPictureSession: PictureInPictureSession
    ) {
        self.playbackController = playbackController
        self.pictureInPictureSession = pictureInPictureSession
        mediaControlAdapter = VLCPictureInPictureMediaController(
            playbackController: playbackController
        )
        super.init(frame: .zero)
        backgroundColor = .black
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    func mediaController() -> VLCPictureInPictureMediaControlling! {
        mediaControlAdapter
    }

    func pictureInPictureReady() -> ((VLCPictureInPictureWindowControlling?) -> Void)! {
        { [weak self] controller in
            DispatchQueue.main.async {
                self?.installWindowController(controller)
            }
        }
    }

    func updatePlaybackState(
        currentTime: Double,
        duration: Double,
        isPaused: Bool,
        isSeekable: Bool
    ) {
        mediaControlAdapter.update(
            currentTime: currentTime,
            duration: duration,
            isPaused: isPaused,
            isSeekable: isSeekable
        )
        windowController?.invalidatePlaybackState()
    }

    func detach() {
        windowController?.stateChangeEventHandler = nil
        if isPictureInPictureActive {
            windowController?.stopPictureInPicture()
        }
        pictureInPictureSession.detach(registrationID: registrationID)
        windowController = nil
        playbackController?.drawable = nil
    }

    private func installWindowController(
        _ controller: VLCPictureInPictureWindowControlling?
    ) {
        windowController?.stateChangeEventHandler = nil
        windowController = controller
        isPictureInPictureActive = false

        controller?.stateChangeEventHandler = { [weak self] isActive in
            DispatchQueue.main.async {
                self?.handleStateChange(isActive: isActive)
            }
        }

        pictureInPictureSession.attach(
            registrationID: registrationID,
            isPossible: controller != nil,
            isActive: false,
            start: { [weak self] in
                self?.windowController?.startPictureInPicture()
            },
            stop: { [weak self] in
                self?.windowController?.stopPictureInPicture()
            }
        )
        controller?.invalidatePlaybackState()
    }

    private func handleStateChange(isActive: Bool) {
        isPictureInPictureActive = isActive
        pictureInPictureSession.update(
            registrationID: registrationID,
            isPossible: windowController != nil,
            isActive: isActive
        )
    }
}

private final class VLCPictureInPictureMediaController:
    NSObject,
    VLCPictureInPictureMediaControlling
{
    private weak var playbackController: VLCPlaybackController?
    private let stateLock = NSLock()
    private var currentTimeMilliseconds: Int64 = 0
    private var durationMilliseconds: Int64 = 0
    private var mediaIsPaused = true
    private var mediaIsSeekable = false

    init(playbackController: VLCPlaybackController) {
        self.playbackController = playbackController
    }

    func update(
        currentTime: Double,
        duration: Double,
        isPaused: Bool,
        isSeekable: Bool
    ) {
        stateLock.lock()
        currentTimeMilliseconds = Self.milliseconds(from: currentTime)
        durationMilliseconds = Self.milliseconds(from: duration)
        mediaIsPaused = isPaused
        mediaIsSeekable = isSeekable
        stateLock.unlock()
    }

    func play() {
        DispatchQueue.main.async { [weak playbackController] in
            playbackController?.resume()
        }
    }

    func pause() {
        DispatchQueue.main.async { [weak playbackController] in
            playbackController?.pause()
        }
    }

    func seek(by offset: Int64, completion: (@Sendable () -> Void)!) {
        DispatchQueue.main.async { [weak playbackController] in
            playbackController?.seek(by: Double(offset) / 1_000)
            completion?()
        }
    }

    func mediaLength() -> Int64 {
        withLockedState { durationMilliseconds }
    }

    func mediaTime() -> Int64 {
        withLockedState { currentTimeMilliseconds }
    }

    func isMediaSeekable() -> Bool {
        withLockedState { mediaIsSeekable }
    }

    func isMediaPlaying() -> Bool {
        withLockedState { !mediaIsPaused }
    }

    private func withLockedState<Value>(_ body: () -> Value) -> Value {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    private static func milliseconds(from seconds: Double) -> Int64 {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int64(min(seconds * 1_000, Double(Int64.max)))
    }
}
#else
final class VLCPictureInPictureView: UIView {
    init(
        playbackController: VLCPlaybackController,
        pictureInPictureSession: PictureInPictureSession
    ) {
        super.init(frame: .zero)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        nil
    }

    func updatePlaybackState(
        currentTime: Double,
        duration: Double,
        isPaused: Bool,
        isSeekable: Bool
    ) {
    }

    func detach() {
    }
}
#endif
#endif
