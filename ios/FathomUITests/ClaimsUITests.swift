import XCTest

/// Files, surveys and settles a claim on a policy the test creates, checking each step on the server.
/// Needs the API at http://127.0.0.1:8000 with seed data loaded.
final class ClaimsUITests: XCTestCase {
    @MainActor private var app: XCUIApplication { XCUIApplication() }
    private let api = "http://127.0.0.1:8000/api"
    private var policyNo: Int?

    override func setUp() async throws {
        continueAfterFailure = false
        // The full file, survey and settle round trip can outrun 3 minutes on a cold simulator.
        executionTimeAllowance = 420
        // A bound policy of our own: $500,000 insured, $10,000 deductible, cover around today.
        let premium = "\(Int.random(in: 1000...9999)).\(Int.random(in: 10...99))"
        let (status, json) = try await send("POST", "policies/", [
            "status": "BOUND", "policy_type": "HULL", "sum_insured": "500000", "deductible": "10000",
            "premium": premium, "issue_date": day(offset: -180), "expiry_date": day(offset: 180),
        ])
        XCTAssertEqual(status, 201)
        let policy = try XCTUnwrap(json as? [String: Any])
        XCTAssertEqual(policy["status"] as? String, "BOUND")
        policyNo = policy["policy_no"] as? Int
    }

    override func tearDown() async throws {
        guard let policyNo else { return }
        // Deleting the policy cascades to its claims and their survey rows.
        let claimIds = try await rows("claims/?policy_no=\(policyNo)").compactMap { $0["claim_id"] as? Int }
        let (deleted, _) = try await send("DELETE", "policies/\(policyNo)")
        XCTAssertEqual(deleted, 204)
        let (gone, _) = try await send("GET", "policies/\(policyNo)")
        XCTAssertEqual(gone, 404)
        for id in claimIds {
            let (claimGone, _) = try await send("GET", "claims/\(id)")
            XCTAssertEqual(claimGone, 404)
            let links = try await rows("assessed-by/?claim_id=\(id)")
            XCTAssertTrue(links.isEmpty)
        }
    }

    @MainActor func testFileSurveyAndSettleClaim() async throws {
        let policyNo = try XCTUnwrap(policyNo)
        let surveyors = try await rows("surveyors/")
        let surveyor = try XCTUnwrap(surveyors.first)
        let surveyorId = try XCTUnwrap(surveyor["surveyor_id"] as? Int)
        let surveyorName = try XCTUnwrap(surveyor["name"] as? String)
        let theme = XCUIDevice.shared.appearance == .dark ? "dark" : "light"
        app.launch()

        // Board.
        app.tabBars.buttons["Claims"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["Open exposure"].waitForExistence(timeout: 10))
        snapshot("claims-1-board-\(theme)")

        // File claim, step 1: pick our policy from the card stack.
        app.buttons["File claim"].tap()
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Policy #\(policyNo),")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        for _ in 0..<10 where !card.isHittable {
            let row = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 0, dy: card.frame.midY))
            row.withOffset(CGVector(dx: 300, dy: 0)).press(forDuration: 0.05, thenDragTo: row.withOffset(CGVector(dx: 60, dy: 0)))
        }
        card.tap()
        snapshot("claims-2-flow-policy-\(theme)")
        app.buttons["Next"].tap()

        // Step 2: today is inside the cover.
        XCTAssertTrue(app.staticTexts["Inside the coverage period"].waitForExistence(timeout: 5))
        snapshot("claims-3-flow-date-\(theme)")
        app.buttons["Next"].tap()

        // Step 3: type the amount.
        let amount = app.textFields["Claim amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("60000")
        snapshot("claims-4-flow-amount-\(theme)")
        app.buttons["Next"].tap()

        // Step 4: review and submit.
        XCTAssertTrue(app.buttons["Submit claim"].waitForExistence(timeout: 5))
        snapshot("claims-5-flow-review-\(theme)")
        app.buttons["Submit claim"].tap()

        // The new claim's detail opens; the server has it as REPORTED.
        XCTAssertTrue(app.buttons["Assign surveyor"].waitForExistence(timeout: 10))
        let filedRows = try await rows("claims/?policy_no=\(policyNo)")
        let filed = try XCTUnwrap(filedRows.first)
        let claimId = try XCTUnwrap(filed["claim_id"] as? Int)
        XCTAssertEqual(filed["claim_amount"] as? String, "60000.00")
        XCTAssertEqual(filed["status"] as? String, "REPORTED")
        snapshot("claims-6-detail-reported-\(theme)")

        // Assign a surveyor through the accessible menu.
        app.buttons["Assign surveyor"].tap()
        let item = app.buttons[surveyorName].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        let surveyed = try await waitForServer {
            let claim = try await self.object("claims/\(claimId)")
            let links = try await self.rows("assessed-by/?claim_id=\(claimId)")
            return claim["status"] as? String == "UNDER_SURVEY" && links.contains { $0["surveyor_id"] as? Int == surveyorId }
        }
        XCTAssertTrue(surveyed, "Expected an assessed-by row and status UNDER_SURVEY")

        // Settle.
        let settle = app.buttons["Settle claim"]
        XCTAssertTrue(settle.waitForExistence(timeout: 5))
        for _ in 0..<20 where !settle.isEnabled { try await Task.sleep(for: .milliseconds(250)) }
        XCTAssertTrue(settle.isEnabled)
        for _ in 0..<5 where !settle.isHittable { app.swipeUp() }
        snapshot("claims-7-detail-before-settle-\(theme)")
        settle.tap()
        let paid = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Paid out")).firstMatch
        XCTAssertTrue(paid.waitForExistence(timeout: 10))
        try await Task.sleep(for: .seconds(2))
        snapshot("claims-8-detail-settled-\(theme)")

        let settled = try await object("claims/\(claimId)")
        XCTAssertEqual(settled["status"] as? String, "SETTLED")
        XCTAssertEqual(settled["settled_amount"] as? String, "50000.00")
        XCTAssertEqual(settled["deductible_applied"] as? String, "10000.00")
    }

    // MARK: - Helpers

    private func day(offset days: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: days, to: .now)!
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    private func send(_ method: String, _ path: String, _ body: [String: Any]? = nil) async throws -> (Int, Any?) {
        var request = URLRequest(url: URL(string: "\(api)/\(path)")!)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, try? JSONSerialization.jsonObject(with: data))
    }

    private func rows(_ path: String) async throws -> [[String: Any]] {
        try await send("GET", path).1 as? [[String: Any]] ?? []
    }

    private func object(_ path: String) async throws -> [String: Any] {
        try await send("GET", path).1 as? [String: Any] ?? [:]
    }

    /// Polls the server until `check` passes or about five seconds go by.
    private func waitForServer(_ check: () async throws -> Bool) async throws -> Bool {
        for _ in 0..<20 {
            if try await check() { return true }
            try await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    /// Saves a screenshot when SCREENSHOT_DIR is set (pass TEST_RUNNER_SCREENSHOT_DIR to xcodebuild).
    @MainActor private func snapshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        add(XCTAttachment(screenshot: screenshot))
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else { return }
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
