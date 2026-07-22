import XCTest
@testable import Orzen

@MainActor
final class StreamPlayerChromeVisibilityControllerTests: XCTestCase {
    func testHideAndRevealChangeVisibility() {
        let controller = StreamPlayerChromeVisibilityController()
        XCTAssertTrue(controller.isVisible)

        controller.hide()
        XCTAssertFalse(controller.isVisible)

        controller.reveal()
        XCTAssertTrue(controller.isVisible)
    }

    func testDisallowedAutoHideKeepsChromeVisible() async throws {
        let controller = StreamPlayerChromeVisibilityController()

        controller.scheduleAutoHide(isAllowed: false)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(controller.isVisible)
    }

    func testCancelAutoHidePreventsScheduledHide() async throws {
        let controller = StreamPlayerChromeVisibilityController()

        controller.scheduleAutoHide(isAllowed: true)
        controller.cancelAutoHide()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(controller.isVisible)
    }
}
