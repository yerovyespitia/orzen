import Foundation

struct ExternalSubtitleCue: Identifiable, Sendable {
    let id: Int
    let startTime: Double
    let endTime: Double
    let text: String
    let placement: Placement

    enum Placement: Sendable {
        case dialogue
        case contextual
    }
}

struct LoadedExternalSubtitle: Sendable {
    let cues: [ExternalSubtitleCue]
    let localFileURL: URL
}

enum ExternalSubtitleResolver {
    static func fetchSubtitles(
        from addons: [LocalAddon],
        type: CinemetaType,
        id: String,
        allowedLanguageCodes: Set<String>
    ) async -> [ExternalSubtitleTrack] {
        await withTaskGroup(of: [ExternalSubtitleTrack].self) { group in
            for addon in addons {
                group.addTask {
                    (try? await StremioSubtitleClient.fetchSubtitles(
                        from: addon,
                        type: type,
                        id: id,
                        allowedLanguageCodes: allowedLanguageCodes
                    )) ?? []
                }
            }

            var allSubtitles: [ExternalSubtitleTrack] = []
            for await addonSubtitles in group {
                allSubtitles.append(contentsOf: addonSubtitles)
            }
            return uniqueSubtitles(from: allSubtitles)
        }
    }

    static func loadCues(from subtitle: ExternalSubtitleTrack) async throws -> [ExternalSubtitleCue] {
        try await loadSubtitle(from: subtitle).cues
    }

    static func loadSubtitle(from subtitle: ExternalSubtitleTrack) async throws -> LoadedExternalSubtitle {
        let localFileURL = try await loadSubtitleFile(from: subtitle)
        let data = try Data(contentsOf: localFileURL)

        guard let content = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw URLError(.cannotDecodeContentData)
        }

        return LoadedExternalSubtitle(cues: parseCues(from: content), localFileURL: localFileURL)
    }

    static func loadSubtitleFile(from subtitle: ExternalSubtitleTrack) async throws -> URL {
        let localFileURL = cachedFileURL(for: subtitle)
        guard !FileManager.default.fileExists(atPath: localFileURL.path) else {
            return localFileURL
        }

        let (data, response) = try await URLSession.shared.data(from: subtitle.url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        try data.write(to: localFileURL, options: .atomic)
        return localFileURL
    }

    private static func cachedFileURL(for subtitle: ExternalSubtitleTrack) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrzenSubtitles", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let supportedExtension = ["srt", "vtt", "ass", "ssa", "sub"]
            .contains(subtitle.url.pathExtension.lowercased())
            ? subtitle.url.pathExtension.lowercased()
            : "srt"
        let cacheKey = subtitle.id
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : "_" }
        return directory
            .appendingPathComponent(String(cacheKey))
            .appendingPathExtension(supportedExtension)
    }

    static func parseCues(from content: String) -> [ExternalSubtitleCue] {
        let normalizedContent = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalizedContent.components(separatedBy: "\n\n")

        return blocks.compactMap { block in
            parseCue(from: block)
        }
        .enumerated()
        .map { index, cue in
            ExternalSubtitleCue(
                id: index,
                startTime: cue.startTime,
                endTime: cue.endTime,
                text: cue.text,
                placement: cue.placement
            )
        }
    }

    static func preferredText(in cues: [ExternalSubtitleCue], at time: Double) -> String? {
        let activeCues = cues.filter { time >= $0.startTime && time <= $0.endTime }
        let dialogueCues = activeCues.filter { $0.placement == .dialogue }
        let preferredCues = dialogueCues.isEmpty ? activeCues : dialogueCues
        let text = preferredCues
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func parseCue(
        from block: String
    ) -> (startTime: Double, endTime: Double, text: String, placement: ExternalSubtitleCue.Placement)? {
        let lines = block
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard let timeLineIndex = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
        let timeParts = lines[timeLineIndex].components(separatedBy: "-->")
        guard timeParts.count == 2,
              let startTime = parseTimestamp(timeParts[0]),
              let endTime = parseTimestamp(timeParts[1]) else {
            return nil
        }

        let text = lines
            .dropFirst(timeLineIndex + 1)
            .map(cleanSubtitleText)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return nil }
        return (
            startTime,
            endTime,
            text,
            cuePlacement(timeLine: lines[timeLineIndex], textLines: Array(lines.dropFirst(timeLineIndex + 1)))
        )
    }

    private static func parseTimestamp(_ value: String) -> Double? {
        let timestamp = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .first?
            .replacingOccurrences(of: ",", with: ".") ?? ""
        let parts = timestamp.split(separator: ":").map(String.init)
        guard parts.count >= 2 else { return nil }

        let secondsText = parts.last ?? "0"
        guard let seconds = Double(secondsText) else { return nil }

        let minutes = Double(parts.dropLast().last ?? "0") ?? 0
        let hours = parts.count > 2 ? (Double(parts.dropLast(2).last ?? "0") ?? 0) : 0
        return hours * 3600 + minutes * 60 + seconds
    }

    private static func cleanSubtitleText(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\{\\[^}]+\}"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cuePlacement(
        timeLine: String,
        textLines: [String]
    ) -> ExternalSubtitleCue.Placement {
        let rawText = textLines.joined(separator: "\n")

        if let alignment = firstIntegerMatch(in: rawText, pattern: #"\\an([1-9])"#) {
            return alignment <= 3 ? .dialogue : .contextual
        }

        if rawText.range(of: #"\\pos\("#, options: .regularExpression) != nil {
            return .contextual
        }

        guard let linePosition = firstDoubleMatch(
            in: timeLine,
            pattern: #"(?:^|\s)line:([0-9]+(?:\.[0-9]+)?)%"#
        ) else {
            return .dialogue
        }

        return linePosition >= 65 ? .dialogue : .contextual
    }

    private static func firstIntegerMatch(in value: String, pattern: String) -> Int? {
        firstMatch(in: value, pattern: pattern).flatMap(Int.init)
    }

    private static func firstDoubleMatch(in value: String, pattern: String) -> Double? {
        firstMatch(in: value, pattern: pattern).flatMap(Double.init)
    }

    private static func firstMatch(in value: String, pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[range])
    }

    private static func uniqueSubtitles(from subtitles: [ExternalSubtitleTrack]) -> [ExternalSubtitleTrack] {
        var seenIDs: Set<String> = []
        return subtitles.filter { subtitle in
            seenIDs.insert(subtitle.id).inserted
        }
    }
}
