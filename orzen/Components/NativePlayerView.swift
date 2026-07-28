import AVKit
import SwiftUI

#if os(macOS)
struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NativePlayerNSView {
        let view = NativePlayerNSView()
        view.player = player
        return view
    }

    func updateNSView(_ nsView: NativePlayerNSView, context: Context) {
        nsView.player = player
    }

    final class NativePlayerNSView: NSView {
        override var wantsUpdateLayer: Bool {
            true
        }

        var player: AVPlayer? {
            get {
                playerLayer.player
            }
            set {
                playerLayer.player = newValue
            }
        }

        private var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }

        override func makeBackingLayer() -> CALayer {
            let layer = AVPlayerLayer()
            layer.videoGravity = .resizeAspect
            layer.backgroundColor = NSColor.black.cgColor
            return layer
        }
    }
}
#else
struct NativePlayerView: UIViewRepresentable {
    let player: AVPlayer
    @ObservedObject var pictureInPictureSession: PictureInPictureSession

    func makeCoordinator() -> Coordinator {
        Coordinator(pictureInPictureSession: pictureInPictureSession)
    }

    func makeUIView(context: Context) -> NativePlayerUIView {
        let view = NativePlayerUIView()
        view.player = player
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: NativePlayerUIView, context: Context) {
        uiView.player = player
        context.coordinator.attach(to: uiView)
    }

    static func dismantleUIView(_ uiView: NativePlayerUIView, coordinator: Coordinator) {
        coordinator.detach()
        uiView.player = nil
    }

    final class Coordinator: NSObject, AVPictureInPictureControllerDelegate {
        private let registrationID = UUID()
        private let pictureInPictureSession: PictureInPictureSession
        private weak var playerView: NativePlayerUIView?
        private var pictureInPictureController: AVPictureInPictureController?
        private var possibleObservation: NSKeyValueObservation?
        private var activeObservation: NSKeyValueObservation?

        init(pictureInPictureSession: PictureInPictureSession) {
            self.pictureInPictureSession = pictureInPictureSession
        }

        func attach(to view: NativePlayerUIView) {
            guard playerView !== view else { return }

            detach()
            playerView = view

            guard AVPictureInPictureController.isPictureInPictureSupported() else { return }

            guard let controller = AVPictureInPictureController(playerLayer: view.playerLayer) else { return }
            controller.delegate = self
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            pictureInPictureController = controller

            pictureInPictureSession.attach(
                registrationID: registrationID,
                isPossible: controller.isPictureInPicturePossible,
                isActive: controller.isPictureInPictureActive,
                start: { [weak self] in
                    self?.startPictureInPicture()
                },
                stop: { [weak self] in
                    self?.stopPictureInPicture()
                }
            )

            possibleObservation = controller.observe(
                \.isPictureInPicturePossible,
                options: [.initial, .new]
            ) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.publishState()
                }
            }
            activeObservation = controller.observe(
                \.isPictureInPictureActive,
                options: [.initial, .new]
            ) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.publishState()
                }
            }
        }

        func detach() {
            possibleObservation?.invalidate()
            possibleObservation = nil
            activeObservation?.invalidate()
            activeObservation = nil
            pictureInPictureSession.detach(registrationID: registrationID)
            pictureInPictureController?.delegate = nil
            pictureInPictureController = nil
            playerView = nil
        }

        private func startPictureInPicture() {
            guard let pictureInPictureController,
                  pictureInPictureController.isPictureInPicturePossible,
                  !pictureInPictureController.isPictureInPictureActive else { return }

            pictureInPictureController.startPictureInPicture()
        }

        private func stopPictureInPicture() {
            guard let pictureInPictureController,
                  pictureInPictureController.isPictureInPictureActive else { return }

            pictureInPictureController.stopPictureInPicture()
        }

        private func publishState() {
            guard let pictureInPictureController else { return }
            pictureInPictureSession.update(
                registrationID: registrationID,
                isPossible: pictureInPictureController.isPictureInPicturePossible,
                isActive: pictureInPictureController.isPictureInPictureActive
            )
        }

        func pictureInPictureControllerDidStartPictureInPicture(
            _ pictureInPictureController: AVPictureInPictureController
        ) {
            publishState()
        }

        func pictureInPictureControllerDidStopPictureInPicture(
            _ pictureInPictureController: AVPictureInPictureController
        ) {
            publishState()
        }

        func pictureInPictureController(
            _ pictureInPictureController: AVPictureInPictureController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            playerView?.setNeedsLayout()
            completionHandler(playerView != nil)
        }
    }
    final class NativePlayerUIView: UIView {
        override static var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var player: AVPlayer? {
            get {
                playerLayer.player
            }
            set {
                playerLayer.player = newValue
            }
        }

        fileprivate var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            configureLayer()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            configureLayer()
        }

        private func configureLayer() {
            playerLayer.videoGravity = .resizeAspect
            playerLayer.backgroundColor = UIColor.black.cgColor
        }
    }
}
#endif
