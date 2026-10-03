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

    // MARK: - Addon subtitles

    func testAddonSubtitleMatchesByAddonSubtitleIDInsteadOfEngineID() {
        // mpv numbers addon subtitles in load order, so "5" can name another file.
        let reorderedTrack = addonSubtitle(id: "5", externalID: "os-1")
        let savedSubtitle = addonSubtitle(id: "6", externalID: "os-2")
        let choice = PlaybackTrackChoice(
            id: "5",
            title: "OpenSubtitles v3: Spanish 2",
            language: "spa",
            isOff: false,
            externalSubtitleID: "os-2",
            externalSubtitleAddonName: "OpenSubtitles v3"
        )

        XCTAssertEqual(
            StreamPlayerTrackPolicy.matchingTrack(for: choice, in: [reorderedTrack, savedSubtitle]),
            savedSubtitle
        )
    }

    func testIOSAddonSubtitleChoiceResolvesOnMPV() {
        let mpvTrack = addonSubtitle(id: "3", externalID: "os-2")
        let iOSChoice = PlaybackTrackChoice(
            id: "external-subtitle-os-2",
            title: "OpenSubtitles v3: Spanish 2",
            language: "spa",
            isOff: false
        )

        XCTAssertEqual(StreamPlayerTrackPolicy.matchingTrack(for: iOSChoice, in: [mpvTrack]), mpvTrack)
    }

    func testAddonSubtitleChoiceWaitsForAddonSubtitlesInsteadOfUsingEmbeddedTrack() {
        let embeddedSpanish = TestFixtures.track(id: "2", title: "Spanish", language: "spa", kind: .subtitle)
        let choice = PlaybackTrackChoice(
            id: "external-subtitle-os-2",
            title: "OpenSubtitles v3: Spanish 2",
            language: "spa",
            isOff: false,
            externalSubtitleID: "os-2"
        )

        XCTAssertNil(
            StreamPlayerTrackPolicy.matchingTrack(
                for: choice,
                in: [embeddedSpanish],
                externalSubtitlesAreLoaded: false
            )
        )
        XCTAssertNil(StreamPlayerTrackPolicy.matchingTrack(for: choice, in: [embeddedSpanish]))
    }

    func testAddonSubtitleFallsBackToSameAddonAndLanguageInNextEpisode() {
        let english = addonSubtitle(id: "external-subtitle-os-10", externalID: "os-10", language: "eng")
        let spanish = addonSubtitle(id: "external-subtitle-os-11", externalID: "os-11", language: "spa")
        let choice = PlaybackTrackChoice(
            id: "external-subtitle-os-2",
            title: "OpenSubtitles v3: Spanish 1",
            language: "spa",
            isOff: false,
            externalSubtitleID: "os-2",
            externalSubtitleAddonName: "OpenSubtitles v3"
        )

        XCTAssertEqual(StreamPlayerTrackPolicy.matchingTrack(for: choice, in: [english, spanish]), spanish)
    }

    func testLegacyMPVAddonSubtitleChoiceDoesNotSelectEmbeddedTrackWithSameID() {
        let embeddedSpanish = TestFixtures.track(id: "5", title: "Spanish", language: "spa", kind: .subtitle)
        let addonSpanish = addonSubtitle(id: "6", externalID: "os-2")
        let legacyChoice = PlaybackTrackChoice(
            id: "5",
            title: "OpenSubtitles v3: Spanish 1 (Spanish)",
            language: "spa",
            isOff: false
        )

        XCTAssertEqual(
            StreamPlayerTrackPolicy.matchingTrack(for: legacyChoice, in: [embeddedSpanish, addonSpanish]),
            addonSpanish
        )
    }

    // MARK: - Embedded tracks across engines

    func testEmbeddedTrackMatchesAcrossEnginesByLanguageAndOrdinal() {
        let firstSpanish = TestFixtures.track(id: "vlc-subtitle-spu/1", title: "Track 1", language: "spa", kind: .subtitle)
        let secondSpanish = TestFixtures.track(id: "vlc-subtitle-spu/2", title: "Track 2", language: "es", kind: .subtitle)
        let mpvChoice = PlaybackTrackChoice(
            id: "3",
            title: "Forced (Spanish)",
            language: "spa",
            isOff: false,
            languageOrdinal: 1
        )

        XCTAssertEqual(
            StreamPlayerTrackPolicy.matchingTrack(for: mpvChoice, in: [firstSpanish, secondSpanish]),
            secondSpanish
        )
    }

    func testEngineIDCollisionWithDifferentLanguageIsIgnored() {
        let french = TestFixtures.track(id: "2", title: "French", language: "fre", kind: .audio)
        let english = TestFixtures.track(id: "3", title: "English", language: "eng", kind: .audio)
        let choice = PlaybackTrackChoice(id: "2", title: "English", language: "en", isOff: false)

        XCTAssertEqual(StreamPlayerTrackPolicy.matchingTrack(for: choice, in: [french, english]), english)
    }

    func testTrackChoiceRecordsLanguageOrdinalForEmbeddedTracks() {
        let first = TestFixtures.track(id: "1", title: "English", language: "eng", kind: .audio)
        let commentary = TestFixtures.track(id: "2", title: "Commentary", language: "en", kind: .audio, isSelected: true)

        let choice = StreamPlayerTrackPolicy.selectedTrackChoice(from: [first, commentary], kind: .audio)

        XCTAssertEqual(choice?.languageOrdinal, 1)
        XCTAssertNil(choice?.externalSubtitleID)
    }

    func testTrackChoiceRecordsAddonSubtitleIdentity() {
        let track = addonSubtitle(id: "7", externalID: "os-2", isSelected: true)

        let choice = StreamPlayerTrackPolicy.trackChoice(from: track, in: [track])

        XCTAssertEqual(choice.externalSubtitleID, "os-2")
        XCTAssertEqual(choice.externalSubtitleAddonName, "OpenSubtitles v3")
        XCTAssertNil(choice.languageOrdinal)
    }

    // MARK: - Requested selections

    func testTrackToSelectIsNilWhenChoiceIsAlreadyInEffect() {
        let off = TestFixtures.track(id: "no", title: "Off", kind: .subtitle, isSelected: true, isOff: true)
        let defaultSubtitle = TestFixtures.track(id: "1", title: "Spanish", language: "spa", kind: .subtitle)
        let offChoice = PlaybackTrackChoice(id: "vlc-subtitle--1", title: "Off", language: nil, isOff: true)

        XCTAssertNil(
            StreamPlayerTrackPolicy.trackToSelect(
                for: offChoice,
                in: [off, defaultSubtitle],
                externalSubtitlesAreLoaded: true
            )
        )
    }

    func testTrackToSelectRestoresOffWhenEngineAutoSelectsSubtitle() {
        let off = TestFixtures.track(id: "no", title: "Off", kind: .subtitle, isOff: true)
        let autoSelected = TestFixtures.track(id: "1", title: "Spanish", language: "spa", kind: .subtitle, isSelected: true)
        let offChoice = PlaybackTrackChoice(id: "vlc-subtitle--1", title: "Off", language: nil, isOff: true)

        XCTAssertEqual(
            StreamPlayerTrackPolicy.trackToSelect(
                for: offChoice,
                in: [off, autoSelected],
                externalSubtitlesAreLoaded: true
            ),
            off
        )
    }

    func testPersistedSelectionsKeepRequestedChoiceOverEngineState() {
        let requestedSubtitle = PlaybackTrackChoice(
            id: "external-subtitle-os-2",
            title: "OpenSubtitles v3: Spanish 1",
            language: "spa",
            isOff: false,
            externalSubtitleID: "os-2"
        )
        let engineAudio = PlaybackTrackChoice(id: "1", title: "English", language: "eng", isOff: false)
        let engineSubtitle = PlaybackTrackChoice(id: "2", title: "Spanish", language: "spa", isOff: false)

        let selections = StreamPlayerTrackPolicy.persistedSelections(
            requested: PlaybackTrackSelections(audio: nil, subtitle: requestedSubtitle),
            engine: PlaybackTrackSelections(audio: engineAudio, subtitle: engineSubtitle)
        )

        XCTAssertEqual(selections.audio, engineAudio)
        XCTAssertEqual(selections.subtitle, requestedSubtitle)
    }

    func testLegacyChoiceDecodesWithoutIdentityFields() throws {
        let data = Data(#"{"id":"2","title":"Spanish","language":"spa","isOff":false}"#.utf8)

        let choice = try JSONDecoder().decode(PlaybackTrackChoice.self, from: data)

        XCTAssertEqual(choice, PlaybackTrackChoice(id: "2", title: "Spanish", language: "spa", isOff: false))
    }

    func testLanguageCodesAreNormalizedAcrossEngines() {
        XCTAssertTrue(StreamPlayerTrackPolicy.languagesMatch("spa", "es"))
        XCTAssertTrue(StreamPlayerTrackPolicy.languagesMatch("es-419", "spa"))
        XCTAssertTrue(StreamPlayerTrackPolicy.languagesMatch(nil, "und"))
        XCTAssertFalse(StreamPlayerTrackPolicy.languagesMatch("eng", "spa"))
    }

    func testRegionalSubtitleVariantsHaveDistinctNames() {
        XCTAssertEqual(PlayerTrackLanguageName.displayName(for: "spa"), "Español")
        XCTAssertNotEqual(
            PlayerTrackLanguageName.displayName(for: "spl"),
            PlayerTrackLanguageName.displayName(for: "spa")
        )
        XCTAssertNotEqual(
            PlayerTrackLanguageName.displayName(for: "pob"),
            PlayerTrackLanguageName.displayName(for: "por")
        )
    }

    private func addonSubtitle(
        id: String,
        externalID: String,
        language: String = "spa",
        isSelected: Bool = false
    ) -> PlayerMediaTrack {
        TestFixtures.track(
            id: id,
            title: "OpenSubtitles v3: Subtitle",
            language: language,
            kind: .subtitle,
            isSelected: isSelected,
            externalSubtitleID: externalID,
            externalSubtitleAddonName: "OpenSubtitles v3"
        )
    }
}
