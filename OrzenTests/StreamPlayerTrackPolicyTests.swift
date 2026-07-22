import XCTest
@testable import Orzen

final class StreamPlayerTrackPolicyTests: XCTestCase {
    func testMatchingTrackPrefersStableIdentifier() {
        let identifierMatch = TestFixtures.track(
            id: "saved-id",
            title: "Renamed English",
            language: "en",
            kind: .audio
        )
        let metadataMatch = TestFixtures.track(
            id: "new-id",
            title: "English",
            language: "en",
            kind: .audio
        )
        let choice = PlaybackTrackChoice(id: "saved-id", title: "English", language: "en", isOff: false)

        XCTAssertEqual(
            StreamPlayerTrackPolicy.matchingTrack(for: choice, in: [metadataMatch, identifierMatch]),
            identifierMatch
        )
    }

    func testMatchingTrackFallsBackToMetadataWhenIdentifiersChange() {
        let track = TestFixtures.track(
            id: "new-id",
            title: "Spanish",
            language: "es",
            kind: .subtitle
        )
        let choice = PlaybackTrackChoice(id: "old-id", title: "Spanish", language: "es", isOff: false)

        XCTAssertEqual(StreamPlayerTrackPolicy.matchingTrack(for: choice, in: [track]), track)
    }

    func testOffStateParticipatesInFallbackMatching() {
        let enabled = TestFixtures.track(
            id: "enabled",
            title: "Off",
            kind: .subtitle,
            isOff: false
        )
        let off = TestFixtures.track(
            id: "off",
            title: "Off",
            kind: .subtitle,
            isOff: true
        )
        let choice = PlaybackTrackChoice(id: "old-off", title: "Off", language: nil, isOff: true)

        XCTAssertEqual(StreamPlayerTrackPolicy.matchingTrack(for: choice, in: [enabled, off]), off)
    }

    func testNoMatchingTrackReturnsNil() {
        let choice = PlaybackTrackChoice(id: "missing", title: "French", language: "fr", isOff: false)
        XCTAssertNil(StreamPlayerTrackPolicy.matchingTrack(for: choice, in: []))
    }

    func testTrackChoicePreservesPersistedIdentityFields() {
        let track = TestFixtures.track(
            id: "subtitle-es",
            title: "Spanish",
            language: "es",
            kind: .subtitle,
            isSelected: true
        )

        XCTAssertEqual(
            StreamPlayerTrackPolicy.trackChoice(from: track),
            PlaybackTrackChoice(id: "subtitle-es", title: "Spanish", language: "es", isOff: false)
        )
    }

    func testSelectedChoiceUsesRequestedTrackKind() {
        let audio = TestFixtures.track(
            id: "audio-en",
            title: "English",
            language: "en",
            kind: .audio,
            isSelected: true
        )
        let subtitle = TestFixtures.track(
            id: "subtitle-es",
            title: "Spanish",
            language: "es",
            kind: .subtitle,
            isSelected: true
        )

        XCTAssertEqual(
            StreamPlayerTrackPolicy.selectedTrackChoice(from: [audio, subtitle], kind: .subtitle)?.id,
            "subtitle-es"
        )
        XCTAssertNil(StreamPlayerTrackPolicy.selectedTrackChoice(from: [audio], kind: .subtitle))
    }

    func testExternalSubtitleTrackIdentifierIsNamespaced() {
        let subtitle = ExternalSubtitleTrack(
            id: "addon-subtitle-1",
            addonName: "Test Addon",
            title: "Spanish",
            language: "es",
            url: URL(string: "https://example.com/subtitle.srt")!
        )

        XCTAssertEqual(
            StreamPlayerTrackPolicy.externalSubtitleTrackID(for: subtitle),
            "external-subtitle-addon-subtitle-1"
        )
    }
}
