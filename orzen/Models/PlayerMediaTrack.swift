import Foundation

struct PlayerMediaTrack: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case audio
        case subtitle

        var mpvName: String {
            switch self {
            case .audio:
                return "audio"
            case .subtitle:
                return "sub"
            }
        }

        var defaultTitle: String {
            switch self {
            case .audio:
                return "Audio"
            case .subtitle:
                return "Subtitle"
            }
        }
    }

    let id: String
    let title: String
    let language: String?
    let kind: Kind
    var isSelected: Bool
    let isOff: Bool
    var externalSubtitleID: String? = nil
    var compatibilityWarning: String? = nil
}

enum PlayerTrackLanguageName {
    private static let iso639TwoLetterCodes: [String: String] = [
        "aar": "aa", "abk": "ab", "afr": "af", "aka": "ak", "amh": "am", "ara": "ar",
        "arg": "an", "asm": "as", "ava": "av", "ave": "ae", "aym": "ay", "aze": "az",
        "bak": "ba", "bam": "bm", "bel": "be", "ben": "bn", "bis": "bi", "bod": "bo",
        "bos": "bs", "bre": "br", "bul": "bg", "cat": "ca", "ces": "cs", "cha": "ch",
        "che": "ce", "chu": "cu", "chv": "cv", "cor": "kw", "cos": "co", "cre": "cr",
        "cym": "cy", "dan": "da", "deu": "de", "div": "dv", "dzo": "dz", "ell": "el",
        "eng": "en", "epo": "eo", "est": "et", "eus": "eu", "ewe": "ee", "fao": "fo",
        "fas": "fa", "fij": "fj", "fin": "fi", "fra": "fr", "fry": "fy", "ful": "ff",
        "gla": "gd", "gle": "ga", "glg": "gl", "glv": "gv", "grn": "gn", "guj": "gu",
        "hat": "ht", "hau": "ha", "heb": "he", "her": "hz", "hin": "hi", "hmo": "ho",
        "hrv": "hr", "hun": "hu", "hye": "hy", "ibo": "ig", "ido": "io", "iii": "ii",
        "iku": "iu", "ile": "ie", "ina": "ia", "ind": "id", "ipk": "ik", "isl": "is",
        "ita": "it", "jav": "jv", "jpn": "ja", "kal": "kl", "kan": "kn", "kas": "ks",
        "kat": "ka", "kau": "kr", "kaz": "kk", "khm": "km", "kik": "ki", "kin": "rw",
        "kir": "ky", "kom": "kv", "kon": "kg", "kor": "ko", "kua": "kj", "kur": "ku",
        "lao": "lo", "lat": "la", "lav": "lv", "lim": "li", "lin": "ln", "lit": "lt",
        "ltz": "lb", "lub": "lu", "lug": "lg", "mah": "mh", "mal": "ml", "mar": "mr",
        "mkd": "mk", "mlg": "mg", "mlt": "mt", "mon": "mn", "mri": "mi", "msa": "ms",
        "mya": "my", "nau": "na", "nav": "nv", "nbl": "nr", "nde": "nd", "ndo": "ng",
        "nep": "ne", "nld": "nl", "nno": "nn", "nob": "nb", "nor": "no", "nya": "ny",
        "oci": "oc", "oji": "oj", "ori": "or", "orm": "om", "oss": "os", "pan": "pa",
        "pli": "pi", "pol": "pl", "por": "pt", "pus": "ps", "que": "qu", "roh": "rm",
        "ron": "ro", "run": "rn", "rus": "ru", "sag": "sg", "san": "sa", "sin": "si",
        "slk": "sk", "slv": "sl", "sme": "se", "smo": "sm", "sna": "sn", "snd": "sd",
        "som": "so", "sot": "st", "spa": "es", "sqi": "sq", "srd": "sc", "srp": "sr",
        "ssw": "ss", "sun": "su", "swa": "sw", "swe": "sv", "tah": "ty", "tam": "ta",
        "tat": "tt", "tel": "te", "tgk": "tg", "tgl": "tl", "tha": "th", "tir": "ti",
        "ton": "to", "tsn": "tn", "tso": "ts", "tuk": "tk", "tur": "tr", "twi": "tw",
        "uig": "ug", "ukr": "uk", "urd": "ur", "uzb": "uz", "ven": "ve", "vie": "vi",
        "vol": "vo", "wln": "wa", "wol": "wo", "xho": "xh", "yid": "yi", "yor": "yo",
        "zha": "za", "zho": "zh", "zul": "zu",
        "alb": "sq", "arm": "hy", "baq": "eu", "chi": "zh", "cze": "cs", "dut": "nl",
        "fre": "fr", "geo": "ka", "ger": "de", "gre": "el", "ice": "is", "mac": "mk",
        "mao": "mi", "may": "ms", "per": "fa", "rum": "ro", "slo": "sk", "tib": "bo",
        "wel": "cy",
        "esp": "es", "spl": "es", "pob": "pt"
    ]

    static func displayName(for language: String?) -> String? {
        guard let language else { return nil }
        let normalized = language
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        guard !normalized.isEmpty, normalized != "und" else { return nil }

        let languageCode = normalized.split(separator: "-").first.map(String.init) ?? normalized
        let twoLetterCode = iso639TwoLetterCodes[languageCode] ?? languageCode

        let languageLocale = Locale(identifier: twoLetterCode)
        guard let name = languageLocale.localizedString(forLanguageCode: twoLetterCode), !name.isEmpty else {
            return nil
        }

        return name.prefix(1).uppercased() + name.dropFirst()
    }
}
