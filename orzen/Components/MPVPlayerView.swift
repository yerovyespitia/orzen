#if os(macOS)
import AppKit
import SwiftUI

struct MPVPlayerView: NSViewRepresentable {
    let url: URL
    let externalSubtitles: [ExternalSubtitleTrack]
    let onEscape: () -> Void
    @ObservedObject var controller: MPVPlaybackController

    func makeNSView(context: Context) -> MPVOpenGLPlayerView {
        let view = MPVOpenGLPlayerView()
        view.controller = controller
        view.onEscape = onEscape
        DispatchQueue.main.async { [weak view] in
            view?.load(url: url, externalSubtitles: externalSubtitles)
        }
        return view
    }

    func updateNSView(_ nsView: MPVOpenGLPlayerView, context: Context) {
        nsView.controller = controller
        nsView.onEscape = onEscape
        DispatchQueue.main.async { [weak nsView] in
            nsView?.load(url: url, externalSubtitles: externalSubtitles)
        }
    }

    static func dismantleNSView(_ nsView: MPVOpenGLPlayerView, coordinator: ()) {
        nsView.shutdown()
    }
}

private final class MPVRenderCallbackTarget {
    weak var view: MPVOpenGLPlayerView?

    init(view: MPVOpenGLPlayerView) {
        self.view = view
    }
}

final class MPVOpenGLPlayerView: NSOpenGLView {
    weak var controller: MPVPlaybackController?
    var onEscape: (() -> Void)?

    private var mpv: OpaquePointer?
    private var renderContext: OpaquePointer?
    private var loadedURL: URL?
    private var externalSubtitles: [ExternalSubtitleTrack] = []
    private var loadedExternalSubtitleIDs = Set<ExternalSubtitleTrack.ID>()
    private var renderCallbackContext: UnsafeMutableRawPointer?
    private var didPrepare = false
    private var stateRefreshTimer: Timer?

    init() {
        let attributes: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFAOpenGLProfile),
            UInt32(NSOpenGLProfileVersion3_2Core),
            UInt32(NSOpenGLPFAColorSize),
            24,
            UInt32(NSOpenGLPFAAlphaSize),
            8,
            UInt32(NSOpenGLPFADoubleBuffer),
            UInt32(NSOpenGLPFAAccelerated),
            0
        ]

        let pixelFormat = NSOpenGLPixelFormat(attributes: attributes)!
        super.init(frame: .zero, pixelFormat: pixelFormat)!
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    deinit {
        shutdown()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case " ":
            togglePlayPause()
        case "f":
            window?.toggleFullScreen(nil)
        case "m":
            toggleMute()
        case String(UnicodeScalar(NSLeftArrowFunctionKey)!):
            seek(by: -5)
        case String(UnicodeScalar(NSRightArrowFunctionKey)!):
            seek(by: 5)
        default:
            super.keyDown(with: event)
        }
    }

    override func prepareOpenGL() {
        super.prepareOpenGL()
        openGLContext?.makeCurrentContext()

        var swapInterval: GLint = 1
        openGLContext?.setValues(&swapInterval, for: .swapInterval)

        didPrepare = true
        startIfReady()
    }

    override func reshape() {
        super.reshape()
        openGLContext?.update()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let renderContext else {
            return
        }

        openGLContext?.makeCurrentContext()

        var viewport = [GLint](repeating: 0, count: 4)
        glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let width = max(1, Int(bounds.width * scale))
        let height = max(1, Int(bounds.height * scale))

        glViewport(0, 0, GLsizei(width), GLsizei(height))

        var fbo = mpv_opengl_fbo(fbo: 0, w: Int32(width), h: Int32(height), internal_format: 0)
        var flipY: Int32 = 1

        withUnsafeMutablePointer(to: &fbo) { fboPointer in
            withUnsafeMutablePointer(to: &flipY) { flipPointer in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(fboPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: UnsafeMutableRawPointer(flipPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                ]

                _ = mpv_render_context_render(renderContext, &params)
            }
        }

        glViewport(viewport[0], viewport[1], viewport[2], viewport[3])
        openGLContext?.flushBuffer()
        mpv_render_context_report_swap(renderContext)
    }

    func load(url: URL, externalSubtitles: [ExternalSubtitleTrack]) {
        if loadedURL == url {
            self.externalSubtitles = externalSubtitles
            addPendingExternalSubtitles()
            return
        }

        loadedURL = url
        self.externalSubtitles = externalSubtitles
        loadedExternalSubtitleIDs = []
        controller?.attach(self)
        controller?.markStarting()
        startIfReady()
    }

    func shutdown() {
        stateRefreshTimer?.invalidate()
        stateRefreshTimer = nil
        controller?.detach(self)
        clearRenderCallbackView()

        if let mpv {
            "stop".withCString { stopCommand in
                var command: [UnsafePointer<CChar>?] = [
                    stopCommand,
                    nil
                ]
                _ = mpv_command(mpv, &command)
            }
        }

        if let renderContext {
            mpv_render_context_set_update_callback(renderContext, nil, nil)
            mpv_render_context_free(renderContext)
            self.renderContext = nil
        }

        if let mpv {
            mpv_terminate_destroy(mpv)
            self.mpv = nil
        }

        loadedURL = nil
        DispatchQueue.main.async { [weak controller] in
            controller?.stop()
        }
    }

    func togglePlayPause() {
        guard let mpv else { return }
        command(arguments: ["cycle", "pause"], handle: mpv)
        refreshPlaybackState()
    }

    func pause() {
        guard let mpv else { return }
        command(arguments: ["set", "pause", "yes"], handle: mpv)
        refreshPlaybackState()
    }

    func seek(to time: Double) {
        guard let mpv else { return }
        command(arguments: ["set", "time-pos", String(time)], handle: mpv)
        refreshPlaybackState()
    }

    func seek(by offset: Double) {
        guard let mpv else { return }
        command(arguments: ["seek", String(offset), "relative"], handle: mpv)
        refreshPlaybackState()
    }

    func setVolume(_ value: Double) {
        guard let mpv else { return }
        command(arguments: ["set", "volume", String(value)], handle: mpv)
        command(arguments: ["set", "mute", value == 0 ? "yes" : "no"], handle: mpv)
        refreshPlaybackState()
    }

    func toggleMute() {
        guard let mpv else { return }
        command(arguments: ["cycle", "mute"], handle: mpv)
        refreshPlaybackState()
    }

    func selectAudioTrack(_ track: PlayerMediaTrack) {
        selectTrack(track, property: "aid")
    }

    func selectSubtitleTrack(_ track: PlayerMediaTrack) {
        selectTrack(track, property: "sid")
    }

    func setSubtitleDelay(_ delay: Double) {
        guard let mpv else { return }
        command(arguments: ["set", "sub-delay", String(delay)], handle: mpv)
    }

    func refreshPlaybackState() {
        guard let mpv else { return }
        let didReachEnd = boolProperty("eof-reached", handle: mpv) ?? false
        let previousDuration = controller?.duration ?? 0
        let resolvedDuration = doubleProperty("duration", handle: mpv) ?? previousDuration

        controller?.didReachEnd = didReachEnd
        controller?.isPaused = (boolProperty("pause", handle: mpv) ?? false) || didReachEnd
        controller?.duration = resolvedDuration
        if let currentTime = doubleProperty("time-pos", handle: mpv) {
            controller?.currentTime = currentTime
        } else if didReachEnd, resolvedDuration > 0 {
            controller?.currentTime = resolvedDuration
        }
        controller?.volume = doubleProperty("volume", handle: mpv) ?? controller?.volume ?? 100
        controller?.isMuted = boolProperty("mute", handle: mpv) ?? false
        controller?.audioTracks = mediaTracks(ofType: .audio, handle: mpv)
        controller?.subtitleTracks = mediaTracks(ofType: .subtitle, handle: mpv)
    }

    private func addPendingExternalSubtitles() {
        guard let mpv, controller?.isRunning == true else { return }

        for subtitle in externalSubtitles where !loadedExternalSubtitleIDs.contains(subtitle.id) {
            command(
                arguments: [
                    "sub-add",
                    subtitle.url.absoluteString,
                    "auto",
                    "\(subtitle.addonName): \(subtitle.title)",
                    subtitle.language ?? ""
                ],
                handle: mpv
            )
            loadedExternalSubtitleIDs.insert(subtitle.id)
        }

        refreshPlaybackState()
    }

    private func selectTrack(_ track: PlayerMediaTrack, property: String) {
        guard let mpv else { return }
        command(arguments: ["set", property, track.isOff ? "no" : track.id], handle: mpv)
        refreshPlaybackState()
    }

    private func startIfReady() {
        guard didPrepare, let loadedURL else { return }
        window?.makeFirstResponder(self)

        if mpv == nil {
            guard initializeMPV() else { return }
        }

        guard let mpv else { return }

        let urlString = loadedURL.absoluteString
        "loadfile".withCString { loadCommand in
            urlString.withCString { urlCString in
                var command: [UnsafePointer<CChar>?] = [
                    loadCommand,
                    urlCString,
                    nil
                ]
                let status = mpv_command(mpv, &command)
                if status < 0 {
                    reportMPVError(prefix: "mpv could not load this source", status: status)
                } else {
                    controller?.markRunning()
                    setSubtitleDelay(controller?.subtitleDelay ?? 0)
                    addPendingExternalSubtitles()
                    refreshPlaybackState()
                    startStateRefreshTimer()
                    needsDisplay = true
                }
            }
        }
    }

    private func initializeMPV() -> Bool {
        guard let handle = mpv_create() else {
            controller?.setError("Orzen could not create a libmpv player.")
            return false
        }

        mpv = handle

        guard setOption("terminal", "no"),
              setOption("config", "no"),
              setOption("osc", "no"),
              setOption("input-default-bindings", "yes"),
              setOption("input-vo-keyboard", "yes"),
              setOption("vo", "libmpv"),
              initialize(handle: handle),
              createRenderContext(handle: handle) else {
            shutdown()
            return false
        }

        return true
    }

    private func setOption(_ name: String, _ value: String) -> Bool {
        guard let mpv else { return false }
        let status = mpv_set_option_string(mpv, name, value)
        guard status >= 0 else {
            reportMPVError(prefix: "mpv rejected option \(name)", status: status)
            return false
        }
        return true
    }

    private func initialize(handle: OpaquePointer) -> Bool {
        let status = mpv_initialize(handle)
        guard status >= 0 else {
            reportMPVError(prefix: "mpv could not initialize", status: status)
            return false
        }
        return true
    }

    private func createRenderContext(handle: OpaquePointer) -> Bool {
        openGLContext?.makeCurrentContext()

        var glInitParams = mpv_opengl_init_params(
            get_proc_address: orzen_mpv_get_proc_address,
            get_proc_address_ctx: nil
        )

        var renderContextPointer: OpaquePointer?

        let status = MPV_RENDER_API_TYPE_OPENGL.withCString { apiTypePointer in
            withUnsafeMutablePointer(to: &glInitParams) { glInitPointer in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: apiTypePointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: UnsafeMutableRawPointer(glInitPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                ]

                return mpv_render_context_create(&renderContextPointer, handle, &params)
            }
        }

        guard status >= 0, let renderContextPointer else {
            reportMPVError(prefix: "mpv could not create an in-app renderer", status: status)
            return false
        }

        renderContext = renderContextPointer

        let pointer = renderCallbackContext ?? Unmanaged.passRetained(MPVRenderCallbackTarget(view: self)).toOpaque()
        renderCallbackContext = pointer
        mpv_render_context_set_update_callback(renderContextPointer, { context in
            guard let context else { return }
            let target = Unmanaged<MPVRenderCallbackTarget>.fromOpaque(context).takeUnretainedValue()
            guard let view = target.view else { return }
            DispatchQueue.main.async {
                view.handleRenderUpdate()
            }
        }, pointer)

        return true
    }

    private func clearRenderCallbackView() {
        guard let renderCallbackContext else { return }
        let target = Unmanaged<MPVRenderCallbackTarget>.fromOpaque(renderCallbackContext).takeUnretainedValue()
        target.view = nil
    }

    private func handleRenderUpdate() {
        guard let renderContext else { return }
        let flags = mpv_render_context_update(renderContext)
        if flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0 {
            needsDisplay = true
        }
    }

    private func reportMPVError(prefix: String, status: Int32) {
        let message = mpv_error_string(status).map { String(cString: $0) } ?? "unknown error"
        controller?.setError("\(prefix): \(message).")
    }

    private func startStateRefreshTimer() {
        stateRefreshTimer?.invalidate()
        stateRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPlaybackState()
            }
        }
    }

    private func command(arguments: [String], handle: OpaquePointer) {
        let cStrings = arguments.map { strdup($0) }
        defer {
            cStrings.forEach { free($0) }
        }

        var command = cStrings.map { UnsafePointer<CChar>($0) }
        command.append(nil)
        _ = mpv_command(handle, &command)
    }

    private func boolProperty(_ name: String, handle: OpaquePointer) -> Bool? {
        var value: Int32 = 0
        let status = name.withCString {
            mpv_get_property(handle, $0, MPV_FORMAT_FLAG, &value)
        }
        guard status >= 0 else { return nil }
        return value != 0
    }

    private func intProperty(_ name: String, handle: OpaquePointer) -> Int? {
        var value: Int64 = 0
        let status = name.withCString {
            mpv_get_property(handle, $0, MPV_FORMAT_INT64, &value)
        }
        guard status >= 0 else { return nil }
        return Int(value)
    }

    private func doubleProperty(_ name: String, handle: OpaquePointer) -> Double? {
        var value: Double = 0
        let status = name.withCString {
            mpv_get_property(handle, $0, MPV_FORMAT_DOUBLE, &value)
        }
        guard status >= 0, value.isFinite else { return nil }
        return value
    }

    private func stringProperty(_ name: String, handle: OpaquePointer) -> String? {
        let valuePointer = name.withCString {
            mpv_get_property_string(handle, $0)
        }
        guard let valuePointer else { return nil }
        defer { mpv_free(valuePointer) }
        return String(cString: valuePointer)
    }

    private func mediaTracks(ofType type: PlayerMediaTrack.Kind, handle: OpaquePointer) -> [PlayerMediaTrack] {
        let trackCount = intProperty("track-list/count", handle: handle) ?? 0
        var tracks: [PlayerMediaTrack] = []

        if type == .subtitle {
            tracks.append(PlayerMediaTrack(id: "no", title: "Off", language: nil, kind: .subtitle, isSelected: false, isOff: true))
        }

        for index in 0..<trackCount {
            guard stringProperty("track-list/\(index)/type", handle: handle) == type.mpvName,
                  let id = stringProperty("track-list/\(index)/id", handle: handle) else {
                continue
            }

            let language = stringProperty("track-list/\(index)/lang", handle: handle)
            let title = stringProperty("track-list/\(index)/title", handle: handle)
            let selected = boolProperty("track-list/\(index)/selected", handle: handle) ?? false
            let externalSubtitleID = type == .subtitle
                ? externalSubtitles.first(where: { "\($0.addonName): \($0.title)" == title })?.id
                : nil

            tracks.append(
                PlayerMediaTrack(
                    id: id,
                    title: resolvedTrackTitle(title: title, language: language, id: id, type: type),
                    language: language,
                    kind: type,
                    isSelected: selected,
                    isOff: false,
                    externalSubtitleID: externalSubtitleID
                )
            )
        }

        if type == .subtitle,
           !tracks.dropFirst().contains(where: \.isSelected),
           tracks.indices.contains(0) {
            tracks[0].isSelected = true
        }

        return tracks
    }

    private func resolvedTrackTitle(title: String?, language: String?, id: String, type: PlayerMediaTrack.Kind) -> String {
        let languageName = PlayerTrackLanguageName.displayName(for: language)

        if let title, !title.isEmpty {
            if let languageName, title.localizedCaseInsensitiveCompare(languageName) != .orderedSame {
                return "\(title) (\(languageName))"
            }

            return title
        }

        if let languageName {
            return languageName
        }

        return "\(type.defaultTitle) \(id)"
    }
}
#endif
