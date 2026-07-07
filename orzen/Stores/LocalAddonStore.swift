import Foundation
import Security

struct LocalAddon: Identifiable, Codable, Equatable, Sendable {
    enum Resource: String, Codable, Sendable {
        case stream
        case subtitles

        var title: String {
            switch self {
            case .stream:
                return "Sources"
            case .subtitles:
                return "Subtitles"
            }
        }
    }

    let id: UUID
    let manifestURL: URL
    let name: String
    let description: String
    let resources: Set<Resource>
    let sourceCategory: StreamSourceCategory
    let isRemovable: Bool

    init(
        id: UUID = UUID(),
        manifestURL: URL,
        name: String,
        description: String,
        resources: Set<Resource> = [.stream],
        sourceCategory: StreamSourceCategory = .general,
        isRemovable: Bool = true
    ) {
        self.id = id
        self.manifestURL = manifestURL
        self.name = name
        self.description = description
        self.resources = resources
        self.sourceCategory = sourceCategory
        self.isRemovable = isRemovable
    }

    var resourceSummary: String {
        resources
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.title)
            .joined(separator: " + ")
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case manifestURL
        case name
        case description
        case resources
        case sourceCategory
        case isRemovable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        manifestURL = try container.decode(URL.self, forKey: .manifestURL)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        resources = try container.decodeIfPresent(Set<Resource>.self, forKey: .resources) ?? [.stream]
        sourceCategory = try container.decodeIfPresent(StreamSourceCategory.self, forKey: .sourceCategory)
            ?? Self.inferredSourceCategory(name: name, description: description, manifestURL: manifestURL)
        isRemovable = try container.decodeIfPresent(Bool.self, forKey: .isRemovable) ?? true
    }

    private static func inferredSourceCategory(
        name: String,
        description: String,
        manifestURL: URL
    ) -> StreamSourceCategory {
        let searchableText = [name, description, manifestURL.absoluteString]
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        let spanishSignals = ["latino", "spanish", "espanol", "castellano"]
        if spanishSignals.contains(where: searchableText.contains) {
            return .spanish
        }

        return .general
    }
}

@MainActor
final class LocalAddonStore: ObservableObject {
    static let shared = LocalAddonStore()
    
    private static let storageKey = "OrzenPrivateAddonsJSON"
    private static let seededAddonIDsKey = "OrzenSeededPrivateAddonIDs"
    private static let keychainService = "com.yerovyespitia.orzen.privateAddons"
    private static let keychainAccount = "privateAddons"
    private static let bundledAddons: [LocalAddon] = [
        LocalAddon(
            id: UUID(uuidString: "E9D21D2D-9D6E-48D5-A4ED-4E2B08BE31FD")!,
            manifestURL: URL(string: "https://torrentio.strem.fun/manifest.json")!,
            name: "Torrentio",
            description: "Default Torrentio stream source.",
            resources: [.stream],
            sourceCategory: .general,
            isRemovable: true
        ),
        LocalAddon(
            id: UUID(uuidString: "D17FB11D-07D2-4EBA-A6A4-67D7BB705B33")!,
            manifestURL: URL(string: "https://opensubtitles-v3.strem.io/manifest.json")!,
            name: "OpenSubtitles v3",
            description: "OpenSubtitles subtitle addon for movies and series.",
            resources: [.subtitles],
            isRemovable: true
        )
    ]
    
    @Published private(set) var addons: [LocalAddon] = []
    
    private init() {
        load()
    }
    
    var streamAddons: [LocalAddon] {
        addons.filter { $0.resources.contains(.stream) }
    }

    var subtitleAddons: [LocalAddon] {
        addons.filter { $0.resources.contains(.subtitles) }
    }
    
    func remove(_ addon: LocalAddon) {
        guard addon.isRemovable else { return }
        addons.removeAll { $0.id == addon.id }
        save()
    }

    func updateManifestURL(for addon: LocalAddon, manifestURL: URL) {
        guard let index = addons.firstIndex(where: { $0.id == addon.id }) else { return }

        addons[index] = LocalAddon(
            id: addon.id,
            manifestURL: manifestURL,
            name: addon.name,
            description: addon.description,
            resources: addon.resources,
            sourceCategory: addon.sourceCategory,
            isRemovable: addon.isRemovable
        )
        save()
    }
    
    private func load() {
        let storedValue = UserDefaults.standard.object(forKey: Self.storageKey)
        let data: Data?
        
        if let storedData = storedValue as? Data {
            data = storedData
        } else if let storedString = storedValue as? String {
            data = storedString.data(using: .utf8)
        } else {
            data = nil
        }
        
        guard let data else {
            if let keychainData = Self.loadKeychainAddonsData() {
                decodeAddons(from: keychainData)
                seedBundledAddonsIfNeeded()
                return
            }
            
            addons = []
            seedBundledAddonsIfNeeded()
            return
        }
        
        decodeAddons(from: data)
        seedBundledAddonsIfNeeded()
    }
    
    private func decodeAddons(from data: Data) {
        do {
            addons = try JSONDecoder().decode([LocalAddon].self, from: data)
        } catch {
            addons = []
        }
    }
    
    private func save() {
        guard let data = try? JSONEncoder().encode(addons) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
        Self.saveKeychainAddonsData(data)
    }

    private func seedBundledAddonsIfNeeded() {
        let seededAddonIDs = Set(UserDefaults.standard.stringArray(forKey: Self.seededAddonIDsKey) ?? [])
        let pendingAddons = Self.bundledAddons.filter { bundledAddon in
            !seededAddonIDs.contains(bundledAddon.id.uuidString)
        }

        guard !pendingAddons.isEmpty else { return }

        addons.append(contentsOf: pendingAddons)

        let updatedSeededAddonIDs = seededAddonIDs.union(pendingAddons.map(\.id.uuidString))
        UserDefaults.standard.set(Array(updatedSeededAddonIDs), forKey: Self.seededAddonIDsKey)
        save()
    }
    
    private static func loadKeychainAddonsData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }
    
    private static func saveKeychainAddonsData(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }
}
