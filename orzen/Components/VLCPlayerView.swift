#if os(iOS)
import AVFoundation
import CoreImage
import CoreMedia
import ObjectiveC.runtime
import SwiftUI
import UIKit
#if canImport(VLCKit)
import VLCKit
#endif

struct VLCPlayerView: UIViewRepresentable {
    @ObservedObject var controller: VLCPlaybackController
    @ObservedObject var pictureInPictureSession: PictureInPictureSession
    let pictureInPictureSubtitleText: String?

    func makeUIView(context: Context) -> VLCPictureInPictureView {
        let view = VLCPictureInPictureView(
            playbackController: controller,
            pictureInPictureSession: pictureInPictureSession
        )
        view.pictureInPictureSubtitleText = pictureInPictureSubtitleText
        view.capturesVLCSubtitleOverlay = controller.subtitleTracks.contains {
            !$0.isOff && $0.isSelected
        }
        controller.drawable = view
        return view
    }

    func updateUIView(_ uiView: VLCPictureInPictureView, context: Context) {
        if controller.drawable == nil {
            controller.drawable = uiView
        }
        uiView.pictureInPictureSubtitleText = pictureInPictureSubtitleText
        uiView.capturesVLCSubtitleOverlay = controller.subtitleTracks.contains {
            !$0.isOff && $0.isSelected
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
    private weak var sampleBufferDisplayView: UIView?
    private weak var vlcSubtitleView: UIView?
    private var subtitleCaptureTimer: Timer?
    private var subtitleCompositor: VLCSubtitleSampleBufferCompositor?

    var capturesVLCSubtitleOverlay = false {
        didSet {
            guard capturesVLCSubtitleOverlay != oldValue,
                  isPictureInPictureActive else { return }
            if capturesVLCSubtitleOverlay {
                startSubtitleCapture()
            } else {
                stopSubtitleCapture()
            }
        }
    }

    var pictureInPictureSubtitleText: String? {
        didSet {
            subtitleCompositor?.subtitleText = pictureInPictureSubtitleText
        }
    }

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
                self?.embedSubtitleViewsInSampleBufferDisplayView()
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
        stopSubtitleCapture()
        subtitleCompositor?.detach()
        subtitleCompositor = nil
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
        subtitleCompositor?.isEnabled = isActive
        if isActive && capturesVLCSubtitleOverlay {
            startSubtitleCapture()
        } else {
            stopSubtitleCapture()
        }
        pictureInPictureSession.update(
            registrationID: registrationID,
            isPossible: windowController != nil,
            isActive: isActive
        )
    }

    private func embedSubtitleViewsInSampleBufferDisplayView() {
        guard let displayView = firstSampleBufferDisplayView(in: self) else { return }
        sampleBufferDisplayView = displayView
        vlcSubtitleView = firstVLCSubtitleView(in: self)

        let compositor = VLCSubtitleSampleBufferCompositor(
            displayLayer: displayView.layer as! AVSampleBufferDisplayLayer
        )
        compositor.subtitleText = pictureInPictureSubtitleText
        compositor.isEnabled = isPictureInPictureActive
        subtitleCompositor?.detach()
        subtitleCompositor = compositor
    }

    private func firstSampleBufferDisplayView(in rootView: UIView) -> UIView? {
        if rootView.layer is AVSampleBufferDisplayLayer {
            return rootView
        }

        for subview in rootView.subviews {
            if let displayView = firstSampleBufferDisplayView(in: subview) {
                return displayView
            }
        }
        return nil
    }

    private func firstVLCSubtitleView(in rootView: UIView) -> UIView? {
        for subview in rootView.subviews {
            let className = NSStringFromClass(type(of: subview))
            if className.localizedCaseInsensitiveContains("Subpicture") {
                return subview
            }
            if let subtitleView = firstVLCSubtitleView(in: subview) {
                return subtitleView
            }
        }
        return nil
    }

    private func startSubtitleCapture() {
        stopSubtitleCapture()
        captureVLCSubtitleOverlay()
        subtitleCaptureTimer = Timer.scheduledTimer(
            withTimeInterval: 0.25,
            repeats: true
        ) { [weak self] _ in
            self?.captureVLCSubtitleOverlay()
        }
    }

    private func stopSubtitleCapture() {
        subtitleCaptureTimer?.invalidate()
        subtitleCaptureTimer = nil
        subtitleCompositor?.capturedSubtitleOverlay = nil
    }

    private func captureVLCSubtitleOverlay() {
        guard let displayView = sampleBufferDisplayView,
              let subtitleView = vlcSubtitleView,
              displayView.bounds.width > 0,
              displayView.bounds.height > 0 else {
            subtitleCompositor?.capturedSubtitleOverlay = nil
            return
        }

        subtitleView.layer.displayIfNeeded()
        let cropRect = subtitleView.convert(displayView.bounds, from: displayView)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = max(
            subtitleView.contentScaleFactor,
            displayView.window?.screen.scale ?? UIScreen.main.scale
        )
        let renderer = UIGraphicsImageRenderer(size: displayView.bounds.size, format: format)
        let image = renderer.image { context in
            context.cgContext.translateBy(x: -cropRect.minX, y: -cropRect.minY)
            subtitleView.layer.render(in: context.cgContext)
        }
        subtitleCompositor?.capturedSubtitleOverlay =
            image.cgImage.flatMap(Self.nonemptySubtitleImage)
    }

    private static func nonemptySubtitleImage(
        _ image: CGImage
    ) -> VLCCapturedSubtitleOverlay? {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return nil }

        let byteCount = CFDataGetLength(data)
        let alphaOffset = image.bitmapInfo.contains(.byteOrder32Little) ? 3 : 0
        let rowBytes = image.bytesPerRow
        let sampleStride = 4
        var minimumX = image.width
        var minimumY = image.height
        var maximumX = -1
        var maximumY = -1

        for y in stride(from: 0, to: image.height, by: sampleStride) {
            let rowOffset = y * rowBytes
            for x in stride(from: 0, to: image.width, by: sampleStride) {
                let offset = rowOffset + x * 4 + alphaOffset
                if offset < byteCount, bytes[offset] != 0 {
                    minimumX = min(minimumX, x)
                    minimumY = min(minimumY, y)
                    maximumX = max(maximumX, x)
                    maximumY = max(maximumY, y)
                }
            }
        }

        guard maximumX >= minimumX, maximumY >= minimumY else { return nil }
        let cropRect = CGRect(
            x: max(minimumX - sampleStride, 0),
            y: max(minimumY - sampleStride, 0),
            width: min(maximumX + sampleStride, image.width - 1)
                - max(minimumX - sampleStride, 0) + 1,
            height: min(maximumY + sampleStride, image.height - 1)
                - max(minimumY - sampleStride, 0) + 1
        ).integral
        guard let croppedImage = image.cropping(to: cropRect) else { return nil }

        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        return VLCCapturedSubtitleOverlay(
            image: croppedImage,
            normalizedFrame: CGRect(
                x: cropRect.minX / imageWidth,
                y: (imageHeight - cropRect.maxY) / imageHeight,
                width: cropRect.width / imageWidth,
                height: cropRect.height / imageHeight
            )
        )
    }
}

private struct VLCCapturedSubtitleOverlay {
    let image: CGImage
    let normalizedFrame: CGRect
}

private final class VLCSubtitleSampleBufferCompositor: NSObject {
    private static let maximumOutputDimension = 1_920
    private static let maximumOutstandingBuffers = 6

    private weak var displayLayer: AVSampleBufferDisplayLayer?
    private let stateLock = NSLock()
    private let renderLock = NSLock()
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private var enabled = false
    private var text: String?
    private var capturedOverlay: VLCCapturedSubtitleOverlay?
    private var pixelBufferPool: CVPixelBufferPool?
    private var poolSize = CGSize.zero
    private var cachedTextOverlay: VLCPositionedTextOverlay?
    private var cachedTextOverlayKey: TextOverlayKey?

    var isEnabled: Bool {
        get {
            stateLock.withLock { enabled }
        }
        set {
            stateLock.withLock {
                enabled = newValue
            }
            if !newValue {
                releaseRenderResources()
            }
        }
    }

    var subtitleText: String? {
        get {
            stateLock.withLock { text }
        }
        set {
            let normalizedText = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            stateLock.withLock {
                text = normalizedText?.isEmpty == false ? normalizedText : nil
            }
        }
    }

    var capturedSubtitleOverlay: VLCCapturedSubtitleOverlay? {
        get {
            stateLock.withLock { capturedOverlay }
        }
        set {
            stateLock.withLock {
                capturedOverlay = newValue
            }
        }
    }

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        super.init()
        VLCSubtitleSampleBufferRegistry.shared.register(self, for: displayLayer)
    }

    func detach() {
        guard let displayLayer else { return }
        VLCSubtitleSampleBufferRegistry.shared.unregister(self, for: displayLayer)
        self.displayLayer = nil
        stateLock.withLock {
            enabled = false
            text = nil
            capturedOverlay = nil
        }
        releaseRenderResources()
    }

    func compositedSampleBuffer(from sourceBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        let state = stateLock.withLock {
            (enabled, text, capturedOverlay)
        }
        guard state.0,
              state.1 != nil || state.2 != nil,
              let sourcePixelBuffer = CMSampleBufferGetImageBuffer(sourceBuffer) else {
            return nil
        }

        renderLock.lock()
        defer { renderLock.unlock() }

        let sourceWidth = CVPixelBufferGetWidth(sourcePixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(sourcePixelBuffer)
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }

        let outputSize = Self.outputSize(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight
        )
        let width = outputSize.width
        let height = outputSize.height
        guard let outputPixelBuffer = makeOutputPixelBuffer(
            width: width,
            height: height
        ) else {
            return nil
        }

        let sourceImage = CIImage(cvPixelBuffer: sourcePixelBuffer)
            .transformed(
                by: CGAffineTransform(
                    scaleX: CGFloat(width) / CGFloat(sourceWidth),
                    y: CGFloat(height) / CGFloat(sourceHeight)
                )
            )
        let overlayImage: CIImage?
        if let subtitleText = state.1 {
            overlayImage = makeTextOverlay(
                subtitleText,
                frameWidth: width,
                frameHeight: height
            ).map {
                CIImage(cgImage: $0.image)
                    .transformed(
                        by: CGAffineTransform(
                            translationX: $0.origin.x,
                            y: $0.origin.y
                        )
                    )
            }
        } else if let capturedOverlay = state.2 {
            let destinationFrame = CGRect(
                x: capturedOverlay.normalizedFrame.minX * CGFloat(width),
                y: capturedOverlay.normalizedFrame.minY * CGFloat(height),
                width: capturedOverlay.normalizedFrame.width * CGFloat(width),
                height: capturedOverlay.normalizedFrame.height * CGFloat(height)
            )
            let scaleX = destinationFrame.width / CGFloat(capturedOverlay.image.width)
            let scaleY = destinationFrame.height / CGFloat(capturedOverlay.image.height)
            overlayImage = CIImage(cgImage: capturedOverlay.image)
                .transformed(
                    by: CGAffineTransform(scaleX: scaleX, y: scaleY)
                )
                .transformed(
                    by: CGAffineTransform(
                        translationX: destinationFrame.minX,
                        y: destinationFrame.minY
                    )
                )
        } else {
            overlayImage = nil
        }

        guard let overlayImage else { return nil }
        imageContext.render(
            overlayImage.composited(over: sourceImage),
            to: outputPixelBuffer,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: colorSpace
        )

        if let attachments = CVBufferCopyAttachments(
            sourcePixelBuffer,
            .shouldPropagate
        ) {
            CVBufferSetAttachments(outputPixelBuffer, attachments, .shouldPropagate)
        }

        var formatDescription: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: outputPixelBuffer,
            formatDescriptionOut: &formatDescription
        ) == noErr,
        let formatDescription else {
            return nil
        }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: .invalid,
            decodeTimeStamp: .invalid
        )
        guard CMSampleBufferGetSampleTimingInfo(
            sourceBuffer,
            at: 0,
            timingInfoOut: &timing
        ) == noErr else {
            return nil
        }

        var outputBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: outputPixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &outputBuffer
        ) == noErr else {
            return nil
        }
        return outputBuffer
    }

    private func makeOutputPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let requestedSize = CGSize(width: width, height: height)
        if pixelBufferPool == nil || poolSize != requestedSize {
            pixelBufferPool = nil
            poolSize = requestedSize

            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [:],
                kCVPixelBufferMetalCompatibilityKey: true
            ]
            let poolAttributes: [CFString: Any] = [
                kCVPixelBufferPoolMinimumBufferCountKey: 3
            ]
            guard CVPixelBufferPoolCreate(
                kCFAllocatorDefault,
                poolAttributes as CFDictionary,
                attributes as CFDictionary,
                &pixelBufferPool
            ) == kCVReturnSuccess else {
                pixelBufferPool = nil
                return nil
            }
        }

        guard let pixelBufferPool else { return nil }
        let auxiliaryAttributes: [CFString: Any] = [
            kCVPixelBufferPoolAllocationThresholdKey:
                Self.maximumOutstandingBuffers
        ]
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            kCFAllocatorDefault,
            pixelBufferPool,
            auxiliaryAttributes as CFDictionary,
            &pixelBuffer
        ) == kCVReturnSuccess else {
            return nil
        }
        return pixelBuffer
    }

    private func makeTextOverlay(
        _ text: String,
        frameWidth: Int,
        frameHeight: Int
    ) -> VLCPositionedTextOverlay? {
        let key = TextOverlayKey(
            text: text,
            width: frameWidth,
            height: frameHeight
        )
        if cachedTextOverlayKey == key {
            return cachedTextOverlay
        }

        let width = CGFloat(frameWidth)
        let height = CGFloat(frameHeight)
        let fontSize = min(max(width * 0.034, 26), 58)
        let horizontalPadding = fontSize * 0.55
        let verticalPadding = fontSize * 0.32
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping

        let fillAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraphStyle
        ]
        let outlineAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .strokeColor: UIColor.black.withAlphaComponent(0.95),
            .strokeWidth: 6,
            .paragraphStyle: paragraphStyle
        ]
        let filledText = NSAttributedString(
            string: text,
            attributes: fillAttributes
        )
        let outlinedText = NSAttributedString(
            string: text,
            attributes: outlineAttributes
        )
        let maximumTextWidth = width * 0.84
        let measuredText = filledText.boundingRect(
            with: CGSize(width: maximumTextWidth, height: height * 0.35),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).integral
        let overlaySize = CGSize(
            width: min(ceil(measuredText.width + horizontalPadding * 2), width),
            height: ceil(measuredText.height + verticalPadding * 2)
        )
        guard overlaySize.width > 0, overlaySize.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: overlaySize, format: format)
        let image = renderer.image { _ in
            UIColor.black.withAlphaComponent(0.42).setFill()
            UIBezierPath(
                roundedRect: CGRect(origin: .zero, size: overlaySize),
                cornerRadius: fontSize * 0.32
            ).fill()
            let textRect = CGRect(
                x: horizontalPadding,
                y: verticalPadding,
                width: overlaySize.width - horizontalPadding * 2,
                height: overlaySize.height - verticalPadding * 2
            )
            outlinedText.draw(in: textRect)
            filledText.draw(in: textRect)
        }

        guard let image = image.cgImage else { return nil }
        let x = (width - overlaySize.width) / 2
        let y = max(height * 0.055, fontSize * 0.75)
        cachedTextOverlay = VLCPositionedTextOverlay(
            image: image,
            origin: CGPoint(x: x, y: y)
        )
        cachedTextOverlayKey = key
        return cachedTextOverlay
    }

    private func releaseRenderResources() {
        renderLock.withLock {
            if let pixelBufferPool {
                CVPixelBufferPoolFlush(pixelBufferPool, .excessBuffers)
            }
            pixelBufferPool = nil
            poolSize = .zero
            cachedTextOverlay = nil
            cachedTextOverlayKey = nil
        }
    }

    private static func outputSize(
        sourceWidth: Int,
        sourceHeight: Int
    ) -> (width: Int, height: Int) {
        let longestDimension = max(sourceWidth, sourceHeight)
        guard longestDimension > maximumOutputDimension else {
            return (sourceWidth, sourceHeight)
        }

        let scale = Double(maximumOutputDimension) / Double(longestDimension)
        let width = max(2, Int(Double(sourceWidth) * scale) / 2 * 2)
        let height = max(2, Int(Double(sourceHeight) * scale) / 2 * 2)
        return (width, height)
    }

    private struct TextOverlayKey: Equatable {
        let text: String
        let width: Int
        let height: Int
    }
}

private struct VLCPositionedTextOverlay {
    let image: CGImage
    let origin: CGPoint
}

private final class VLCSubtitleSampleBufferRegistry {
    static let shared = VLCSubtitleSampleBufferRegistry()

    private let lock = NSLock()
    private let compositors = NSMapTable<
        AVSampleBufferDisplayLayer,
        VLCSubtitleSampleBufferCompositor
    >(keyOptions: .weakMemory, valueOptions: .strongMemory)

    private init() {
        guard let originalMethod = class_getInstanceMethod(
            AVSampleBufferDisplayLayer.self,
            NSSelectorFromString("enqueueSampleBuffer:")
        ),
        let replacementMethod = class_getInstanceMethod(
            AVSampleBufferDisplayLayer.self,
            #selector(AVSampleBufferDisplayLayer.orzen_enqueueSampleBuffer(_:))
        ) else {
            return
        }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }

    func register(
        _ compositor: VLCSubtitleSampleBufferCompositor,
        for layer: AVSampleBufferDisplayLayer
    ) {
        lock.withLock {
            compositors.setObject(compositor, forKey: layer)
        }
    }

    func unregister(
        _ compositor: VLCSubtitleSampleBufferCompositor,
        for layer: AVSampleBufferDisplayLayer
    ) {
        lock.withLock {
            guard compositors.object(forKey: layer) === compositor else { return }
            compositors.removeObject(forKey: layer)
        }
    }

    func compositor(
        for layer: AVSampleBufferDisplayLayer
    ) -> VLCSubtitleSampleBufferCompositor? {
        lock.withLock {
            compositors.object(forKey: layer)
        }
    }
}

private extension AVSampleBufferDisplayLayer {
    @objc func orzen_enqueueSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        autoreleasepool {
            let compositedBuffer = VLCSubtitleSampleBufferRegistry.shared
                .compositor(for: self)?
                .compositedSampleBuffer(from: sampleBuffer)
            orzen_enqueueSampleBuffer(compositedBuffer ?? sampleBuffer)
        }
    }
}

private extension NSLock {
    func withLock<Value>(_ body: () -> Value) -> Value {
        lock()
        defer { unlock() }
        return body()
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
    var pictureInPictureSubtitleText: String?
    var capturesVLCSubtitleOverlay = false

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
