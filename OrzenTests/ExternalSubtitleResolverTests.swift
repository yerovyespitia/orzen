import XCTest
@testable import Orzen

final class ExternalSubtitleResolverTests: XCTestCase {
    func testParsesSRTTimestampsAndRemovesFormattingTags() {
        let content = """
        1
        00:00:01,500 --> 00:00:03,250
        <i>Hello</i>

        2
        00:01:00.000 --> 00:01:02.000
        {\\an8}Top label
        """

        let cues = ExternalSubtitleResolver.parseCues(from: content)

        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].startTime, 1.5, accuracy: 0.001)
        XCTAssertEqual(cues[0].endTime, 3.25, accuracy: 0.001)
        XCTAssertEqual(cues[0].text, "Hello")
        XCTAssertEqual(cues[0].placement, .dialogue)
        XCTAssertEqual(cues[1].startTime, 60, accuracy: 0.001)
        XCTAssertEqual(cues[1].placement, .contextual)
    }

    func testPreferredTextPrioritizesDialogueOverContextualCue() {
        let cues = [
            ExternalSubtitleCue(id: 0, startTime: 1, endTime: 3, text: "Context", placement: .contextual),
            ExternalSubtitleCue(id: 1, startTime: 1, endTime: 3, text: "Dialogue", placement: .dialogue)
        ]

        XCTAssertEqual(ExternalSubtitleResolver.preferredText(in: cues, at: 2), "Dialogue")
    }

    func testPreferredTextReturnsNilOutsideCueRange() {
        let cue = ExternalSubtitleCue(
            id: 0,
            startTime: 1,
            endTime: 3,
            text: "Dialogue",
            placement: .dialogue
        )

        XCTAssertNil(ExternalSubtitleResolver.preferredText(in: [cue], at: 4))
    }

    func testUniqueSubtitlesDropsSameFileFromDuplicateAddons() {
        let url = URL(string: "https://example.com/subtitle.srt")!
        let first = ExternalSubtitleTrack(id: "addon-a-1", addonName: "OpenSubtitles v3", title: "Spanish 1", language: "spa", url: url)
        let duplicate = ExternalSubtitleTrack(id: "addon-b-1", addonName: "OpenSubtitles v3", title: "Spanish 1", language: "spa", url: url)

        XCTAssertEqual(ExternalSubtitleResolver.uniqueSubtitles(from: [first, duplicate]), [first])
    }

    @MainActor
    func testDuplicateSubtitleAddonsCollapseToBundledAddon() {
        let manifestURL = URL(string: "https://opensubtitles-v3.strem.io/manifest.json")!
        let bundledID = UUID(uuidString: "D17FB11D-07D2-4EBA-A6A4-67D7BB705B33")!
        let manuallyInstalled = LocalAddon(
            manifestURL: manifestURL,
            name: "OpenSubtitles v3",
            description: "",
            resources: [.subtitles]
        )
        let bundled = LocalAddon(
            id: bundledID,
            manifestURL: manifestURL,
            name: "OpenSubtitles v3",
            description: "",
            resources: [.subtitles]
        )
        let streamAddon = TestFixtures.addon()

        let addons = LocalAddonStore.deduplicatedAddons([manuallyInstalled, streamAddon, bundled])

        XCTAssertEqual(addons.map(\.id), [bundledID, streamAddon.id])
    }
}
