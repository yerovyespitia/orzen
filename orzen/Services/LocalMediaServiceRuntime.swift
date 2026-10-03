import Foundation
#if os(macOS)
import SystemConfiguration
#endif

/// Process identity keeps the library writable only in the background service.
enum LocalMediaServiceRuntime {
    static let appIdentifier = "com.yerovyespitia.orzen"
    static var serviceIdentifier: String {
        if isService { return Bundle.main.bundleIdentifier ?? appIdentifier + ".LocalMedia" }
        return (Bundle.main.bundleIdentifier ?? appIdentifier) + ".LocalMedia"
    }
    static var isService: Bool {
        #if ORZEN_LOCAL_MEDIA_SERVICE
        true
        #else
        false
        #endif
    }

    static func testValue(_ key: String) -> String? {
        #if DEBUG
        return ProcessInfo.processInfo.environment[key]
            ?? (Bundle.main.object(forInfoDictionaryKey: "OrzenServiceTestEnvironment") as? [String: String])?[key]
        #else
        return nil
        #endif
    }

    static var defaults: UserDefaults {
        #if DEBUG
        if let suite = testValue("ORZEN_SERVICE_TEST_DEFAULTS") {
            return UserDefaults(suiteName: suite)!
        }
        #endif
        return .standard
    }

    #if os(macOS)
    // Read the configured Bonjour name without blocking the main actor on reverse DNS.
    static var hostName: String {
        guard let name = SCDynamicStoreCopyLocalHostName(nil) as String? else { return "localhost" }
        return name.hasSuffix(".local") ? name : name + ".local"
    }

    static var computerName: String {
        SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "Mac"
    }

    static func prepareServiceDefaults(from previous: UserDefaults? = UserDefaults(suiteName: appIdentifier),
                                       into defaults: UserDefaults = LocalMediaServiceRuntime.defaults) {
        guard !defaults.bool(forKey: "localMedia.serviceMigration.v1") else { return }
        // Copy once into the helper's own domain. The two processes never write the same stores.
        for key in ["localMedia.pairingCode", "localMedia.accessToken", "localMedia.torznabEndpoint",
                    "OrzenPlaybackProgressJSON", "OrzenLocalPlaybackProgressTombstonesJSON",
                    "OrzenCollectionsJSON"] {
            if let value = previous?.object(forKey: key) { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: "localMedia.serviceMigration.v1")
    }

    static func credentials(defaults: UserDefaults = LocalMediaServiceRuntime.defaults) -> (code: String, token: String) {
        let code = defaults.string(forKey: "localMedia.pairingCode")
            ?? String(format: "%06d", Int.random(in: 0...999999))
        let token = defaults.string(forKey: "localMedia.accessToken")
            ?? UUID().uuidString + UUID().uuidString
        defaults.set(code, forKey: "localMedia.pairingCode")
        defaults.set(token, forKey: "localMedia.accessToken")
        return (code, token)
    }
    #endif
}

struct LocalMediaLibrarySnapshot: Codable {
    let instanceID: UUID
    let revision: UInt64
    let versions: [LocalMediaVersion]
    var storageError: String? = nil
}

/// Request order handles restarts; revision handles repeated responses within one process.
struct LocalMediaSnapshotCursor {
    private(set) var instanceID: UUID?
    private(set) var revision: UInt64 = 0
    private(set) var lastRequest: UInt64 = 0

    mutating func accepts(_ snapshot: LocalMediaLibrarySnapshot, request: UInt64) -> Bool {
        guard request >= lastRequest else { return false }
        guard instanceID != snapshot.instanceID || snapshot.revision >= revision else { return false }
        instanceID = snapshot.instanceID
        revision = snapshot.revision
        lastRequest = request
        return true
    }
}

struct LocalMediaSearchConfiguration: Codable {
    let endpoint: String
    let apiKey: String
}
