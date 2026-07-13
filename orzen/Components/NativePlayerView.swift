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

    func makeCoordinator() -> Coordinator {
        Coordinator()
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
        private weak var playerView: NativePlayerUIView?
        private var pictureInPictureController: AVPictureInPictureController?
        private var backgroundObserver: NSObjectProtocol?

        func attach(to view: NativePlayerUIView) {
            guard playerView !== view else { return }

            detach()
            playerView = view

            guard AVPictureInPictureController.isPictureInPictureSupported() else { return }

            guard let controller = AVPictureInPictureController(playerLayer: view.playerLayer) else { return }
            controller.delegate = self
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            pictureInPictureController = controller
            backgroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.startPictureInPictureIfNeeded()
            }
        }

        func detach() {
            if let backgroundObserver {
                NotificationCenter.default.removeObserver(backgroundObserver)
                self.backgroundObserver = nil
            }
            pictureInPictureController?.delegate = nil
            pictureInPictureController = nil
            playerView = nil
        }

        private func startPictureInPictureIfNeeded() {
            guard playerView?.player?.rate ?? 0 > 0,
                  let pictureInPictureController,
                  pictureInPictureController.isPictureInPicturePossible,
                  !pictureInPictureController.isPictureInPictureActive else { return }

            pictureInPictureController.startPictureInPicture()
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
