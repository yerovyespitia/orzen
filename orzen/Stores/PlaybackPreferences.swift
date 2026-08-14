import Foundation

enum PlaybackSeekInterval: Int, CaseIterable, Identifiable, Sendable {
    case five = 5
    case ten = 10
    case fifteen = 15
    case thirty = 30

    static let defaultValue: Self = .ten
    static let storageKey = "playback.seekIntervalSeconds"

    var id: Int { rawValue }

    var seconds: Double { Double(rawValue) }

    var displayValue: String { "\(rawValue)s" }

    var backwardSystemImage: String {
        "\(rawValue).arrow.trianglehead.counterclockwise"
    }

    var forwardSystemImage: String {
        "\(rawValue).arrow.trianglehead.clockwise"
    }

    static func resolved(rawValue: Int) -> Self {
        Self(rawValue: rawValue) ?? defaultValue
    }
}
