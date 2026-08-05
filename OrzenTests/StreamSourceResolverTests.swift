import XCTest
@testable import Orzen

final class StreamSourceResolverTests: XCTestCase {
    func testStreamSourcePersistsExactAddonIdentity() throws {
        let addonID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let source = TestFixtures.source(addonID: addonID)

        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(StreamSource.self, from: data)

        XCTAssertEqual(decoded.addonID, addonID)
    }

    func testLegacyStreamSourceInfersAddonIdentityFromStableIdentifier() throws {
        let addonID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let legacySource = TestFixtures.source(
            id: "\(addonID.uuidString)-0-legacy-source",
            addonID: nil
        )

        let data = try JSONEncoder().encode(legacySource)
        let decoded = try JSONDecoder().decode(StreamSource.self, from: data)

        XCTAssertEqual(decoded.addonID, addonID)
    }

    func testExactAddonIdentityAvoidsEquivalentConfigurations() {
        let first = TestFixtures.addon(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            name: "Torrentio RD"
        )
        let exact = TestFixtures.addon(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            name: "Torrentio RD"
        )
        let source = TestFixtures.source(addonID: exact.id, addonName: exact.name)

        XCTAssertEqual(
            StreamSourceResolver.sourceAddons(for: source, from: [first, exact]),
            [exact]
        )
    }

    func testRemovedExactAddonDoesNotFallBackToEquivalentConfiguration() {
        let removedAddonID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let replacement = TestFixtures.addon(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            name: "Torrentio RD"
        )
        let source = TestFixtures.source(addonID: removedAddonID, addonName: replacement.name)

        XCTAssertTrue(
            StreamSourceResolver.sourceAddons(for: source, from: [replacement]).isEmpty
        )
    }

    func testLegacyAddonIdentityKeepsNameAndCategoryMigrationFallback() {
        let first = TestFixtures.addon(name: "Torrentio RD")
        let second = TestFixtures.addon(name: "Torrentio RD")
        let source = TestFixtures.source(id: "legacy-source", addonName: "Torrentio RD")

        XCTAssertEqual(
            StreamSourceResolver.sourceAddons(for: source, from: [first, second]),
            [first, second]
        )
    }

    func testSourceResultsYieldWithoutWaitingForSlowestAddon() async {
        let slow = TestFixtures.addon(name: "Slow")
        let fast = TestFixtures.addon(name: "Fast")
        var resultIDs: [LocalAddon.ID] = []

        for await result in StreamSourceResolver.sourceResults(
            from: [slow, fast],
            type: .movie,
            id: "tt123",
            fetch: { addon, _, _ in
                let delay: UInt64 = addon.id == slow.id ? 100_000_000 : 10_000_000
                try? await Task.sleep(nanoseconds: delay)
                return [TestFixtures.source(addonID: addon.id, addonName: addon.name)]
            }
        ) {
            resultIDs.append(result.addon.id)
        }

        XCTAssertEqual(resultIDs, [fast.id, slow.id])
    }

    func testSourceAddonTitleDistinguishesLanguageConfiguration() {
        let general = TestFixtures.addon(name: "Torrentio RD")
        let latino = TestFixtures.addon(
            name: "Torrentio RD",
            sourceCategory: .language("latino")
        )

        XCTAssertEqual(general.sourceSelectionTitle, "Torrentio RD")
        XCTAssertEqual(latino.sourceSelectionTitle, "Torrentio RD · Latino")
    }

    func testSourceAddonAvailabilityOmitsAddonsWithoutSources() {
        let torrentio = TestFixtures.addon(id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, name: "Torrentio")
        let comet = TestFixtures.addon(id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!, name: "Comet")
        let source = TestFixtures.source(addonName: torrentio.name)

        XCTAssertEqual(
            SourceAddonResultsPolicy.availableAddons(
                from: [torrentio, comet],
                sourcesByAddonID: [torrentio.id: [source], comet.id: []]
            ),
            [torrentio]
        )
    }

    func testSourceAddonAllSelectionAppendsSourcesInCompletionOrder() {
        let torrentio = TestFixtures.addon(id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, name: "Torrentio")
        let comet = TestFixtures.addon(id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!, name: "Comet")
        let torrentioSource = TestFixtures.source(id: "torrentio", addonName: torrentio.name)
        let cometSource = TestFixtures.source(id: "comet", addonName: comet.name)

        XCTAssertEqual(
            SourceAddonResultsPolicy.sources(
                for: nil,
                addons: [comet, torrentio],
                sourcesByAddonID: [
                    torrentio.id: [torrentioSource],
                    comet.id: [cometSource]
                ]
            ),
            [cometSource, torrentioSource]
        )
    }

    func testMatchingSourcePrefersIdentifier() {
        let stored = TestFixtures.source(
            id: "stable",
            title: "Stored",
            url: URL(string: "https://example.com/old.m3u8")
        )
        let identifierMatch = TestFixtures.source(
            id: "stable",
            title: "Renamed",
            url: URL(string: "https://example.com/new.m3u8")
        )
        let urlMatch = TestFixtures.source(
            id: "other",
            title: "Stored",
            url: stored.playbackURL
        )

        XCTAssertEqual(
            StreamSourceResolver.matchingSource(for: stored, in: [urlMatch, identifierMatch]),
            identifierMatch
        )
    }

    func testMatchingSourceFallsBackToPlaybackURL() {
        let url = URL(string: "https://example.com/stable.m3u8")!
        let stored = TestFixtures.source(id: "old", title: "Old", url: url)
        let refreshed = TestFixtures.source(id: "new", title: "New", url: url)

        XCTAssertEqual(StreamSourceResolver.matchingSource(for: stored, in: [refreshed]), refreshed)
    }

    func testMatchingSourceFallsBackToTitle() {
        let stored = TestFixtures.source(id: "old", title: "Provider 1080p")
        let refreshed = TestFixtures.source(
            id: "new",
            title: "Provider 1080p",
            url: URL(string: "https://example.com/new.m3u8")
        )

        XCTAssertEqual(StreamSourceResolver.matchingSource(for: stored, in: [refreshed]), refreshed)
    }

    func testNoExactMatchUsesPlatformFallback() {
        let stored = TestFixtures.source(id: "stored", title: "Stored")
        let unsupported = TestFixtures.source(id: "mkv", title: "A MKV", url: URL(string: "https://example.com/a.mkv"))
        let supported = TestFixtures.source(id: "hls", title: "B HLS", url: URL(string: "https://example.com/b.m3u8"))

        #if os(iOS)
        XCTAssertEqual(StreamSourceResolver.matchingSource(for: stored, in: [unsupported, supported]), supported)
        #else
        XCTAssertEqual(StreamSourceResolver.matchingSource(for: stored, in: [unsupported, supported]), unsupported)
        #endif
    }
}
