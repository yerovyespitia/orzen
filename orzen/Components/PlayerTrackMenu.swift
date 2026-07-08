import SwiftUI

struct PlayerTrackMenu: View, Equatable {
    let systemName: String
    let help: String
    let emptyTitle: String
    let tracks: [PlayerMediaTrack]
    let onSelect: (PlayerMediaTrack) -> Void

    static func == (lhs: PlayerTrackMenu, rhs: PlayerTrackMenu) -> Bool {
        lhs.systemName == rhs.systemName
            && lhs.help == rhs.help
            && lhs.emptyTitle == rhs.emptyTitle
            && lhs.tracks == rhs.tracks
    }

    var body: some View {
        Menu {
            if tracks.isEmpty {
                Text(emptyTitle)
            } else if tracks.contains(where: { $0.kind == .subtitle }) {
                subtitleMenuItems
            } else {
                ForEach(tracks) { track in
                    trackButton(track, title: track.title)
                }
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(tracks.isEmpty ? 0.55 : 0.92))
                .frame(width: buttonSize, height: buttonSize)
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(helpText)
        .disabled(tracks.isEmpty)
    }

    private var buttonSize: CGFloat {
        #if os(iOS)
        return 34
        #else
        return 28
        #endif
    }

    @ViewBuilder
    private var subtitleMenuItems: some View {
        ForEach(offTracks) { track in
            trackButton(track, title: track.title)
        }

        if !originalSubtitleTracks.isEmpty {
            Section("Original") {
                ForEach(originalSubtitleTracks) { track in
                    trackButton(track, title: track.title)
                }
            }
        }

        ForEach(addonSubtitleGroups, id: \.name) { group in
            Section(group.name) {
                ForEach(group.tracks) { track in
                    trackButton(track, title: addonSubtitleTitle(for: track))
                }
            }
        }
    }

    private var selectedTrack: PlayerMediaTrack? {
        tracks.first(where: { $0.isSelected && !$0.isOff })
    }

    private var helpText: String {
        if let selectedTrack {
            return "\(help): \(selectedTrack.title)"
        }

        if tracks.contains(where: \.isOff) {
            return "\(help): Off"
        }

        return help
    }

    private var offTracks: [PlayerMediaTrack] {
        tracks.filter(\.isOff)
    }

    private var originalSubtitleTracks: [PlayerMediaTrack] {
        tracks.filter { !$0.isOff && addonName(for: $0) == nil }
    }

    private var addonSubtitleGroups: [(name: String, tracks: [PlayerMediaTrack])] {
        let groupedTracks = Dictionary(grouping: tracks.filter { !$0.isOff }) { track in
            addonName(for: track)
        }

        return groupedTracks.compactMap { name, tracks in
            guard let name else { return nil }
            return (name, tracks)
        }
        .sorted { $0.name < $1.name }
    }

    private func trackButton(_ track: PlayerMediaTrack, title: String) -> some View {
        Button {
            onSelect(track)
        } label: {
            if track.isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func addonName(for track: PlayerMediaTrack) -> String? {
        guard track.kind == .subtitle,
              let separatorRange = track.title.range(of: ": ") else {
            return nil
        }

        let prefix = String(track.title[..<separatorRange.lowerBound])
        return prefix.isEmpty ? nil : prefix
    }

    private func addonSubtitleTitle(for track: PlayerMediaTrack) -> String {
        guard let separatorRange = track.title.range(of: ": ") else {
            return track.title
        }

        return String(track.title[separatorRange.upperBound...])
    }
}
