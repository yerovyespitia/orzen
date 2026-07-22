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
}
