import Foundation

struct SubtitleLanguageOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let languageCodes: Set<String>
}

@MainActor
final class SubtitlePreferencesStore: ObservableObject {
    static let shared = SubtitlePreferencesStore()

    static let availableLanguages: [SubtitleLanguageOption] = [
        SubtitleLanguageOption(id: "eng", title: "English", languageCodes: ["eng", "en"]),
        SubtitleLanguageOption(id: "spa", title: "Spanish", languageCodes: ["spa", "es", "spl", "es-419", "es-mx"]),
        SubtitleLanguageOption(id: "ita", title: "Italian", languageCodes: ["ita", "it"]),
        SubtitleLanguageOption(id: "fra", title: "French", languageCodes: ["fra", "fre", "fr"]),
        SubtitleLanguageOption(id: "deu", title: "German", languageCodes: ["deu", "ger", "de"]),
        SubtitleLanguageOption(id: "por", title: "Portuguese", languageCodes: ["por", "pob", "pt", "pt-br", "pt-pt"]),
        SubtitleLanguageOption(id: "rus", title: "Russian", languageCodes: ["rus", "ru"]),
        SubtitleLanguageOption(id: "ara", title: "Arabic", languageCodes: ["ara", "ar"])
    ]

    private static let selectedLanguageIDsKey = "OrzenSubtitleSelectedLanguageIDs"
    private static let defaultLanguageIDs = Set(["eng", "spa", "es-419", "ita"])

    @Published private(set) var selectedLanguageIDs: Set<String>

    private init() {
        let storedIDs = UserDefaults.standard.stringArray(forKey: Self.selectedLanguageIDsKey)
        selectedLanguageIDs = Self.normalizedLanguageIDs(storedIDs.map(Set.init) ?? Self.defaultLanguageIDs)
    }

    var selectedLanguageCodes: Set<String> {
        Self.availableLanguages
            .filter { selectedLanguageIDs.contains($0.id) }
            .flatMap(\.languageCodes)
            .reduce(into: Set<String>()) { codes, code in
                codes.insert(code.lowercased())
            }
    }

    func isSelected(_ option: SubtitleLanguageOption) -> Bool {
        selectedLanguageIDs.contains(option.id)
    }

    func setSelected(_ isSelected: Bool, for option: SubtitleLanguageOption) {
        if isSelected {
            selectedLanguageIDs.insert(option.id)
        } else {
            selectedLanguageIDs.remove(option.id)
        }

        save()
    }

    private func save() {
        UserDefaults.standard.set(Array(selectedLanguageIDs), forKey: Self.selectedLanguageIDsKey)
    }

    private static func normalizedLanguageIDs(_ ids: Set<String>) -> Set<String> {
        var normalizedIDs = ids

        if normalizedIDs.contains("es-419") {
            normalizedIDs.insert("spa")
            normalizedIDs.remove("es-419")
        }

        return normalizedIDs
    }
}
