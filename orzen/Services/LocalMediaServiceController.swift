#if os(macOS)
import AppKit
import ServiceManagement

@MainActor
final class LocalMediaServiceController: ObservableObject {
    static let shared = LocalMediaServiceController()
    @Published private(set) var isRunning = false
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var loginMessage: String?
    @Published private(set) var startsAtLogin = false
    let pairingCode: String
    let hostName: String
    private var loginOperationError: String?
    private var observation: Task<Void, Never>?
    private let loginService = SMAppService.loginItem(identifier: LocalMediaServiceRuntime.serviceIdentifier)

    private init() {
        pairingCode = LocalMediaServiceRuntime.credentials().code
        hostName = LocalMediaServiceRuntime.hostName
        refreshLoginStatus()
    }

    func observe() {
        guard observation == nil, !LocalMediaServiceRuntime.isService,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        observation = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func start() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            let url = Bundle.main.bundleURL.appending(path: "Contents/Library/LoginItems/OrzenLocalMedia.app")
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw LocalMediaError.engine("The Local Media service is missing. Rebuild or reinstall Orzen.")
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.addsToRecentItems = false
            #if DEBUG
            var environment: [String: String] = [:]
            for key in ["ORZEN_SERVICE_TEST_DEFAULTS", "ORZEN_SERVICE_TEST_ROOT", "ORZEN_SERVICE_TEST_PORT", "LLVM_PROFILE_FILE"] {
                environment[key] = LocalMediaServiceRuntime.testValue(key)
            }
            configuration.environment = environment
            #endif
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            for _ in 0..<30 {
                await refresh()
                if isRunning { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            if !isRunning { throw LocalMediaError.engine("Local Media did not start. Check its menu bar status.") }
            if UserDefaults.standard.object(forKey: "localMedia.startsAtLogin") == nil {
                await setStartsAtLogin(true)
            }
            try await sendSearchConfiguration()
        } catch { errorMessage = error.localizedDescription }
    }

    func stop() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: LocalMediaServiceRuntime.serviceIdentifier) {
            app.terminate()
        }
        isRunning = false
        errorMessage = "Local Media is stopped. Start it to access your Mac library."
    }

    func setStartsAtLogin(_ enabled: Bool) async {
        loginOperationError = nil
        do {
            if enabled {
                if loginService.status != .enabled { try loginService.register() }
            } else if loginService.status != .notRegistered {
                try await loginService.unregister()
            }
            UserDefaults.standard.set(enabled, forKey: "localMedia.startsAtLogin")
        } catch { loginOperationError = error.localizedDescription }
        refreshLoginStatus()
    }

    func refreshLoginStatus() {
        startsAtLogin = loginService.status == .enabled || loginService.status == .requiresApproval
        if loginService.status == .requiresApproval {
            loginMessage = "Allow Orzen Local Media in System Settings → General → Login Items."
        } else if loginService.status == .enabled || loginService.status == .notRegistered {
            loginMessage = loginOperationError
        }
    }

    func sendSearchConfiguration() async throws {
        let settings = TorznabSettingsStore.shared
        try await RemoteLocalMediaClient.shared.configureSearch(
            LocalMediaSearchConfiguration(endpoint: settings.configuration?.endpoint.absoluteString ?? "",
                                          apiKey: settings.configuration?.apiKey ?? ""))
    }

    private func refresh() async {
        refreshLoginStatus()
        do {
            try await RemoteLocalMediaClient.shared.refreshLibrary()
            isRunning = true
            errorMessage = nil
            await PlaybackProgressStore.shared.synchronizeLocalProgress()
            await CollectionStore.shared.synchronizeLocalCollections()
        } catch {
            isRunning = false
            errorMessage = "Local Media is unavailable. Start the service to access your library."
        }
    }
}
#endif
