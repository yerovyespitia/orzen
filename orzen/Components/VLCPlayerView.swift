#if os(iOS)
import AVKit
import SwiftUI
import UIKit
#if canImport(VLCKit)
import VLCKit
#endif

struct VLCPlayerView: UIViewRepresentable {
    @ObservedObject var controller: VLCPlaybackController
    let pictureInPictureSubtitleText: String?

    func makeUIView(context: Context) -> VLCPictureInPictureView {
        let view = VLCPictureInPictureView()
        view.pictureInPictureSubtitleText = pictureInPictureSubtitleText
        controller.drawable = view
        return view
    }

    func updateUIView(_ uiView: VLCPictureInPictureView, context: Context) {
        if controller.drawable == nil {
            controller.drawable = uiView
        }
        uiView.pictureInPictureSubtitleText = pictureInPictureSubtitleText
    }

    static func dismantleUIView(_ uiView: VLCPictureInPictureView, coordinator: ()) {
    }
}

final class VLCPictureInPictureView: UIView, AVPictureInPictureControllerDelegate {
    private let contentViewController = VLCPictureInPictureContentViewController()
    private var pictureInPictureController: AVPictureInPictureController?
    private var backgroundObserver: NSObjectProtocol?

    var pictureInPictureSubtitleText: String? {
        didSet {
            contentViewController.subtitleText = pictureInPictureSubtitleText
        }
    }

    override init(frame: CGRect) {
        super.init(frame: .zero)
        backgroundColor = .black
        isUserInteractionEnabled = false
        configurePictureInPicture()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        isUserInteractionEnabled = false
        configurePictureInPicture()
    }

    deinit {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
    }

    private func configurePictureInPicture() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }

        contentViewController.renderingView = self
        contentViewController.preferredContentSize = CGSize(width: 16, height: 9)

        let contentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: self,
            contentViewController: contentViewController
        )
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        pictureInPictureController = controller

        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.startPictureInPictureIfNeeded()
        }
    }

    private func startPictureInPictureIfNeeded() {
        guard !subviews.isEmpty,
              let pictureInPictureController,
              pictureInPictureController.isPictureInPicturePossible,
              !pictureInPictureController.isPictureInPictureActive else { return }

        pictureInPictureController.startPictureInPicture()
    }

    fileprivate func moveRenderingSubviews(to destination: UIView) {
        contentViewController.sourceContentSize = bounds.size
        moveSubviews(from: self, to: destination)
    }

    fileprivate func restoreRenderingSubviews(from source: UIView) {
        moveSubviews(from: source, to: self)
    }

    private func moveSubviews(from source: UIView, to destination: UIView) {
        for view in source.subviews {
            view.removeFromSuperview()
            view.frame = destination.bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            destination.addSubview(view)
        }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

final class VLCPictureInPictureContentViewController: AVPictureInPictureVideoCallViewController {
    weak var renderingView: VLCPictureInPictureView?
    private let renderingContainer = UIView()
    private let subtitleContainer = UIView()
    private let subtitleLabel = UILabel()
    private var subtitleBottomConstraint: NSLayoutConstraint?
    private var subtitleLeadingConstraint: NSLayoutConstraint?
    private var subtitleTrailingConstraint: NSLayoutConstraint?
    private var subtitleLabelLeadingConstraint: NSLayoutConstraint?
    private var subtitleLabelTrailingConstraint: NSLayoutConstraint?
    private var subtitleLabelTopConstraint: NSLayoutConstraint?
    private var subtitleLabelBottomConstraint: NSLayoutConstraint?

    var sourceContentSize: CGSize = .zero {
        didSet {
            guard isViewLoaded else { return }
            updateSubtitleMetrics()
        }
    }

    var subtitleText: String? {
        didSet {
            guard isViewLoaded else { return }
            updateSubtitle()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        renderingContainer.backgroundColor = .black
        renderingContainer.isUserInteractionEnabled = false
        view.addSubview(renderingContainer)

        subtitleContainer.translatesAutoresizingMaskIntoConstraints = false
        subtitleContainer.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        subtitleContainer.layer.cornerRadius = 8
        subtitleContainer.layer.cornerCurve = .continuous
        subtitleContainer.isUserInteractionEnabled = false

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        subtitleLabel.textAlignment = .center
        subtitleLabel.textColor = .white
        subtitleLabel.numberOfLines = 0
        subtitleLabel.layer.shadowColor = UIColor.black.cgColor
        subtitleLabel.layer.shadowOpacity = 0.95
        subtitleLabel.layer.shadowRadius = 2
        subtitleLabel.layer.shadowOffset = CGSize(width: 0, height: 1)

        subtitleContainer.addSubview(subtitleLabel)
        view.addSubview(subtitleContainer)
        subtitleBottomConstraint = subtitleContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        subtitleLeadingConstraint = subtitleContainer.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor)
        subtitleTrailingConstraint = subtitleContainer.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor)
        subtitleLabelLeadingConstraint = subtitleLabel.leadingAnchor.constraint(equalTo: subtitleContainer.leadingAnchor)
        subtitleLabelTrailingConstraint = subtitleLabel.trailingAnchor.constraint(equalTo: subtitleContainer.trailingAnchor)
        subtitleLabelTopConstraint = subtitleLabel.topAnchor.constraint(equalTo: subtitleContainer.topAnchor)
        subtitleLabelBottomConstraint = subtitleLabel.bottomAnchor.constraint(equalTo: subtitleContainer.bottomAnchor)

        NSLayoutConstraint.activate(
            [
                subtitleContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                subtitleBottomConstraint,
                subtitleLeadingConstraint,
                subtitleTrailingConstraint,
                subtitleLabelLeadingConstraint,
                subtitleLabelTrailingConstraint,
                subtitleLabelTopConstraint,
                subtitleLabelBottomConstraint
            ].compactMap { $0 }
        )
        updateSubtitleMetrics()
        updateSubtitle()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        renderingContainer.frame = view.bounds
        updateSubtitleMetrics()
        view.bringSubviewToFront(subtitleContainer)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        renderingView?.moveRenderingSubviews(to: renderingContainer)
    }

    override func viewDidDisappear(_ animated: Bool) {
        renderingView?.restoreRenderingSubviews(from: renderingContainer)
        super.viewDidDisappear(animated)
    }

    private func updateSubtitle() {
        let text = subtitleText?.trimmingCharacters(in: .whitespacesAndNewlines)
        subtitleLabel.text = text
        subtitleContainer.isHidden = text?.isEmpty != false
    }

    private func updateSubtitleMetrics() {
        let sourceWidth = max(sourceContentSize.width, view.bounds.width)
        let rawScale = sourceWidth > 0 ? view.bounds.width / sourceWidth : 1
        let scale = min(max(rawScale, 0.55), 1)

        subtitleLabel.font = .systemFont(ofSize: 18 * scale, weight: .semibold)
        subtitleLabel.layer.shadowRadius = 2 * scale
        subtitleLabel.layer.shadowOffset = CGSize(width: 0, height: scale)
        subtitleContainer.layer.cornerRadius = 8 * scale
        subtitleBottomConstraint?.constant = -12 * scale
        subtitleLeadingConstraint?.constant = 12 * scale
        subtitleTrailingConstraint?.constant = -12 * scale
        subtitleLabelLeadingConstraint?.constant = 12 * scale
        subtitleLabelTrailingConstraint?.constant = -12 * scale
        subtitleLabelTopConstraint?.constant = 8 * scale
        subtitleLabelBottomConstraint?.constant = -8 * scale
    }
}
#endif
