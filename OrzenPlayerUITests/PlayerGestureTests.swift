#if os(iOS)
import XCTest

@MainActor
final class PlayerGestureTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeRight
        app = XCUIApplication()
        app.launchArguments = ["--player-interaction-tests", "-playback.seekIntervalSeconds", "10"]
        app.launch()
        XCTAssertTrue(app.staticTexts["player-test-scale"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testPinchExpandsAndRestoresWithControlsVisible() {
        assertState("player-test-chrome", equals: "visible")
        assertPinchExpandsAndRestores()
        assertState("player-test-chrome", equals: "visible")
    }

    func testPinchExpandsAndRestoresWithControlsHidden() {
        backgroundPoint.tap()
        assertState("player-test-chrome", equals: "hidden")
        assertPinchExpandsAndRestores()
        assertState("player-test-chrome", equals: "hidden")
    }

    func testSingleTapStillTogglesControlsAndDoubleTapStillSeeks() {
        backgroundPoint.tap()
        assertState("player-test-chrome", equals: "hidden")
        backgroundPoint.tap()
        assertState("player-test-chrome", equals: "visible")

        // Exercise seeking on both touch layers, without depending on the saved interval.
        backgroundPoint.doubleTap()
        assertTimeIsLessThan(60)
        let position = Int(app.staticTexts["player-test-time"].label)!
        backgroundPoint.tap()
        assertState("player-test-chrome", equals: "hidden")
        backgroundPoint.doubleTap()
        assertTimeIsLessThan(position)
    }

    private var backgroundPoint: XCUICoordinate {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.35))
    }

    private func assertPinchExpandsAndRestores() {
        assertState("player-test-scale", equals: "1.00")
        app.windows.firstMatch.pinch(withScale: 1.6, velocity: 1)
        assertState("player-test-scale", equals: "1.22")
        app.windows.firstMatch.pinch(withScale: 0.6, velocity: -1)
        assertState("player-test-scale", equals: "1.00")
    }

    private func assertState(_ identifier: String, equals expected: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app.staticTexts[identifier])
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
            "Expected \(identifier) to be \(expected); got \(app.staticTexts[identifier].label)",
            file: file, line: line
        )
    }

    private func assertTimeIsLessThan(_ position: Int, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate { [self] _, _ in
            guard let time = Int(app.staticTexts["player-test-time"].label) else { return false }
            return time < position
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }
}
#endif
