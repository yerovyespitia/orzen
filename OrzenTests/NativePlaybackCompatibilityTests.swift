import XCTest
@testable import Orzen

final class NativePlaybackCompatibilityTests: XCTestCase {
    func testKnownExtensionsMapToExpectedCompatibility() {
        XCTAssertEqual(compatibility(for: "video.m3u8"), .supported)
        XCTAssertEqual(compatibility(for: "video.mp4"), .likely)
        XCTAssertEqual(compatibility(for: "video.ts"), .likely)

        guard case .unsupported = compatibility(for: "video.mkv") else {
            return XCTFail("MKV must remain unsupported by native playback")
        }
    }

    func testDescriptionSignalsAreUsedWhenURLHasNoExtension() {
        let hls = TestFixtures.source(
            description: "Adaptive HLS stream",
            url: URL(string: "https://example.com/playback")
        )
        let webm = TestFixtures.source(
            description: "VP9 WebM encode",
            url: URL(string: "https://example.com/playback")
        )

        XCTAssertEqual(NativePlaybackCompatibilityResolver.compatibility(for: hls), .supported)
        guard case .unsupported = NativePlaybackCompatibilityResolver.compatibility(for: webm) else {
            return XCTFail("WebM signal must remain unsupported")
        }
    }

    func testUnknownDirectHTTPSourceDefaultsToSupported() {
        let source = TestFixtures.source(url: URL(string: "https://example.com/playback"))
        XCTAssertEqual(NativePlaybackCompatibilityResolver.compatibility(for: source), .supported)
    }

    func testMissingAndNonHTTPURLsAreUnsupported() {
        guard case .unsupported = NativePlaybackCompatibilityResolver.compatibility(
            for: TestFixtures.source(url: nil)
        ) else {
            return XCTFail("Missing URL must be unsupported")
        }

        guard case .unsupported = NativePlaybackCompatibilityResolver.compatibility(
            for: TestFixtures.source(url: URL(string: "ftp://example.com/video.mp4"))
        ) else {
            return XCTFail("Non-HTTP URL must be unsupported")
        }
    }

    func testNativeSortingUsesCompatibilityBeforeTitle() {
        let unsupported = TestFixtures.source(id: "unsupported", title: "A", url: URL(string: "https://example.com/a.mkv"))
        let likely = TestFixtures.source(id: "likely", title: "B", url: URL(string: "https://example.com/b.mp4"))
        let supportedZ = TestFixtures.source(id: "supported-z", title: "Zulu", url: URL(string: "https://example.com/z.m3u8"))
        let supportedA = TestFixtures.source(id: "supported-a", title: "Alpha", url: URL(string: "https://example.com/a.m3u8"))

        XCTAssertEqual(
            NativePlaybackCompatibilityResolver.sortedForNativePlayback([
                unsupported,
                likely,
                supportedZ,
                supportedA
            ]).map(\.id),
            ["supported-a", "supported-z", "likely", "unsupported"]
        )
    }

    func testBestNativeSourceSkipsUnsupportedCandidates() {
        let unsupported = TestFixtures.source(id: "unsupported", url: URL(string: "https://example.com/a.mkv"))
        let supported = TestFixtures.source(id: "supported", url: URL(string: "https://example.com/a.m3u8"))

        XCTAssertEqual(
            NativePlaybackCompatibilityResolver.bestNativeSource(in: [unsupported, supported]),
            supported
        )
        XCTAssertNil(NativePlaybackCompatibilityResolver.bestNativeSource(in: [unsupported]))
    }

    private func compatibility(for path: String) -> NativePlaybackCompatibility {
        NativePlaybackCompatibilityResolver.compatibility(
            for: TestFixtures.source(url: URL(string: "https://example.com/\(path)"))
        )
    }
}
