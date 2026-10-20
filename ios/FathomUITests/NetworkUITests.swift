import XCTest

/// Drives the Network tab against a running backend and checks each change reached the database.
/// Needs the API at http://127.0.0.1:8000 with seed data loaded.
final class NetworkUITests: XCTestCase {
    @MainActor private var app: XCUIApplication { XCUIApplication() }

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor func testClientCreateEditDelete() async throws {
        let name = "Test Shipper \(Int.random(in: 1000...9999))"
        app.launch()

        // List: seed clients load.
        app.tabBars.buttons["Network"].tap()
        XCTAssertTrue(app.staticTexts["Oceanic Shipping Corp"].waitForExistence(timeout: 10))
        snapshot("network-clients")

        // Create.
        app.buttons["New client"].tap()
        app.textFields["Name"].tap()
        app.textFields["Name"].typeText(name)
        app.textFields["Address"].tap()
        app.textFields["Address"].typeText("1 Test Quay")
        app.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
        let created = try await serverClient(named: name)
        XCTAssertEqual(created?["address"] as? String, "1 Test Quay")

        // Edit from the profile.
        app.staticTexts[name].tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))
        snapshot("network-profile")
        app.buttons["Edit"].tap()
        let address = app.textFields["Address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        address.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "1 Test Quay".count))
        address.typeText("2 Updated Quay")
        app.buttons["Save"].tap()
        // Profile facts merge label and value into one accessibility element.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "2 Updated Quay")).firstMatch.waitForExistence(timeout: 5))
        let edited = try await serverClient(named: name)
        XCTAssertEqual(edited?["address"] as? String, "2 Updated Quay")

        // Delete.
        app.buttons["Delete"].tap()
        snapshot("network-delete-dialog")
        app.buttons["Delete client"].tap()
        XCTAssertTrue(app.staticTexts["Oceanic Shipping Corp"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[name].exists)
        let deleted = try await serverClient(named: name)
        XCTAssertNil(deleted)
    }

    @MainActor func testUnderwritersGroupByDepartment() {
        app.launch()
        app.tabBars.buttons["Network"].tap()
        app.buttons["Underwriters"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["James Montgomery"].waitForExistence(timeout: 10))
        snapshot("network-underwriters")
        app.buttons["Reinsurers"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Swiss Marine Reinsurance AG"].waitForExistence(timeout: 5))
        snapshot("network-reinsurers")
        app.staticTexts["Swiss Marine Reinsurance AG"].tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))
        snapshot("network-reinsurer-profile")
    }

    // MARK: - Helpers

    private func serverClient(named name: String) async throws -> [String: Any]? {
        let url = URL(string: "http://127.0.0.1:8000/api/clients/?limit=500")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let clients = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return clients.first { $0["name"] as? String == name }
    }

    /// Saves a screenshot when SCREENSHOT_DIR is set (pass TEST_RUNNER_SCREENSHOT_DIR to xcodebuild).
    @MainActor private func snapshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        add(XCTAttachment(screenshot: screenshot))
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else { return }
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
