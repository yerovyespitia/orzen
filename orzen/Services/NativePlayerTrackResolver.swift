import AVKit

enum NativePlayerTrackResolver {
    static func tracks(
        in item: AVPlayerItem?,
        for characteristic: AVMediaCharacteristic,
        kind: PlayerMediaTrack.Kind,
        includesOffOption: Bool
    ) -> [PlayerMediaTrack] {
        guard let item,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: characteristic) else {
            return includesOffOption ? [offTrack(kind: kind, isSelected: true)] : []
        }

        let selectedOption = item.currentMediaSelection.selectedMediaOption(in: group)
        var tracks: [PlayerMediaTrack] = []

        if includesOffOption {
            tracks.append(offTrack(kind: kind, isSelected: selectedOption == nil))
        }

        tracks.append(
            contentsOf: group.options.enumerated().map { index, option in
                PlayerMediaTrack(
                    id: trackID(kind: kind, index: index),
                    title: trackTitle(option: option, fallback: "\(kind.defaultTitle) \(index + 1)"),
                    language: option.extendedLanguageTag ?? option.locale?.identifier,
                    kind: kind,
                    isSelected: option == selectedOption,
                    isOff: false
                )
            }
        )

        return tracks
    }

    static func select(
        _ track: PlayerMediaTrack,
        in item: AVPlayerItem?,
        for characteristic: AVMediaCharacteristic
    ) {
        guard let item,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: characteristic) else { return }

        if track.isOff {
            item.select(nil, in: group)
            return
        }

        let index = trackIndex(from: track.id)
        guard group.options.indices.contains(index) else { return }
        item.select(group.options[index], in: group)
    }

    static func offTrack(kind: PlayerMediaTrack.Kind, isSelected: Bool) -> PlayerMediaTrack {
        PlayerMediaTrack(
            id: "\(kind.rawValue)-off",
            title: "Off",
            language: nil,
            kind: kind,
            isSelected: isSelected,
            isOff: true
        )
    }

    private static func trackID(kind: PlayerMediaTrack.Kind, index: Int) -> String {
        "native-\(kind.rawValue)-\(index)"
    }

    private static func trackIndex(from id: String) -> Int {
        Int(id.split(separator: "-").last ?? "") ?? 0
    }

    private static func trackTitle(option: AVMediaSelectionOption, fallback: String) -> String {
        let language = option.extendedLanguageTag ?? option.locale?.identifier
        let languageName = PlayerTrackLanguageName.displayName(for: language)

        if let languageName, !option.displayName.isEmpty, option.displayName.localizedCaseInsensitiveCompare(languageName) != .orderedSame {
            return "\(option.displayName) (\(languageName))"
        }

        return languageName ?? (option.displayName.isEmpty ? fallback : option.displayName)
    }
}
