import AppKit
import Combine
import Darwin

@main
struct LocalMediaServiceMain {
    @MainActor
    static func main() {
        LocalMediaServiceRuntime.prepareServiceDefaults()
        let app = NSApplication.shared
        let delegate = LocalMediaServiceDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
private final class LocalMediaServiceDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // NSWorkspace avoids duplicate launches; this lock also covers direct executable launches.
        guard LocalMediaServiceLock.acquire() else { NSApp.terminate(nil); return }
        LocalMediaServer.shared.start()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "externaldrive.connected.to.line.below", accessibilityDescription: "Orzen Local Media")
        updateMenu()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateMenu() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        LocalMediaServer.shared.stop()
    }

    private func updateMenu() {
        let server = LocalMediaServer.shared
        let versions = LocalMediaLibraryStore.shared.versions
        let active = versions.filter { $0.status == .downloading || $0.status == .queued }.count
        let menu = NSMenu()
        menu.addItem(withTitle: "Orzen Local Media", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: server.isRunning ? "Available on local network" : (server.errorMessage ?? "Starting…"), action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "\(active) active downloads · \(versions.filter { $0.status == .completed }.count) completed", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Pairing code: \(server.pairingCode)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let open = menu.addItem(withTitle: "Open Orzen", action: #selector(openOrzen), keyEquivalent: "")
        open.target = self
        let folder = menu.addItem(withTitle: "Open Media Folder", action: #selector(openFolder), keyEquivalent: "")
        folder.target = self
        menu.addItem(.separator())
        let stop = menu.addItem(withTitle: "Stop Local Media…", action: #selector(stop), keyEquivalent: "")
        stop.target = self
        statusItem?.menu = menu
    }

    @objc private func openOrzen() {
        var url = Bundle.main.bundleURL
        for _ in 0..<4 { url.deleteLastPathComponent() }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    @objc private func openFolder() { NSWorkspace.shared.open(LocalMediaLibraryStore.shared.rootURL) }

    @objc private func stop() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Stop Local Media?"
        alert.informativeText = "Downloads and iPhone playback will stop. You can start the service again in Orzen Settings. It will still start at your next login if enabled."
        alert.addButton(withTitle: "Stop Local Media")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { NSApp.terminate(nil) }
    }
}

private enum LocalMediaServiceLock {
    private static var descriptor: Int32 = -1
    static func acquire() -> Bool {
        #if DEBUG
        let testFolder = LocalMediaServiceRuntime.testValue("ORZEN_SERVICE_TEST_ROOT").map { URL(fileURLWithPath: $0) }
        #else
        let testFolder: URL? = nil
        #endif
        let folder = testFolder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Orzen", directoryHint: .isDirectory)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { return false }
        descriptor = open(folder.appending(path: "local-media.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        return descriptor >= 0 && flock(descriptor, LOCK_EX | LOCK_NB) == 0
    }
}
