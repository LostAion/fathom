import XCTest

/// Drives the Bridge dashboard and the Concurrency Lab against a running backend.
final class BridgeUITests: XCTestCase {
    @MainActor private var app: XCUIApplication { XCUIApplication() }

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor func testDashboardAndMapStrip() {
        app.launch()
        XCTAssertTrue(app.staticTexts["Total sum insured"].waitForExistence(timeout: 10))
        snapshot("bridge-top")

        app.swipeUp()
        app.buttons["Loss ratio"].tap()
        snapshot("bridge-loss-ratio")
        app.buttons["Table"].tap()
        XCTAssertTrue(app.staticTexts["Incurred"].waitForExistence(timeout: 3))
        snapshot("bridge-table")

        let map = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Map of")).firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        app.swipeUp()
        snapshot("bridge-bottom")
        // Let the scroll settle, or the tap only stops it.
        sleep(1)
        map.tap()
        // The tab bar is minimised after scrolling, and other tabs stay in the accessibility
        // tree, so check that the Bridge map is no longer on screen.
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == false"), object: map)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
        snapshot("bridge-opened-fleet")
    }

    @MainActor func testConcurrencyLab() async throws {
        app.launch()
        XCTAssertTrue(app.staticTexts["Total sum insured"].waitForExistence(timeout: 10))
        let lab = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Concurrency Lab")).firstMatch
        for _ in 0..<6 where !lab.isHittable { app.swipeUp() }
        lab.tap()

        app.buttons["Without locking"].tap()
        app.buttons["Run on MariaDB"].tap()
        XCTAssertTrue(app.staticTexts["Lost update"].waitForExistence(timeout: 15))
        sleep(3)
        snapshot("lab-unsafe")

        app.buttons["With row lock"].tap()
        app.buttons["Run on MariaDB"].tap()
        XCTAssertTrue(app.staticTexts["Consistent"].waitForExistence(timeout: 15))
        sleep(3)
        snapshot("lab-locked")
        app.swipeUp()
        snapshot("lab-log")

        let cleanup = app.buttons["Remove demo records"]
        for _ in 0..<6 where !cleanup.isHittable { app.swipeUp() }
        cleanup.tap()
        XCTAssertTrue(cleanup.waitForNonExistence(timeout: 15))
        let demoClients = try await serverRows("clients").filter { $0["name"] as? String == "Concurrency Demo Shipper" }
        XCTAssertTrue(demoClients.isEmpty)
    }

    // MARK: - Helpers

    private func serverRows(_ resource: String) async throws -> [[String: Any]] {
        let url = URL(string: "http://127.0.0.1:8000/api/\(resource)/?limit=500")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
    }

    /// Saves a screenshot when SCREENSHOT_DIR is set (pass TEST_RUNNER_SCREENSHOT_DIR to xcodebuild).
    @MainActor private func snapshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        add(XCTAttachment(screenshot: screenshot))
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else { return }
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
