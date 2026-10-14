import XCTest

/// Drives the Policies tab against a running backend and checks each change reached the database.
/// Needs the API at http://127.0.0.1:8000 with seed data loaded.
final class PoliciesUITests: XCTestCase {
    @MainActor private var app: XCUIApplication { XCUIApplication() }

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor func testIssueQuoteBindReinsureDelete() async throws {
        app.launch()

        // Wallet.
        app.tabBars.buttons["Policies"].tap()
        XCTAssertTrue(app.buttons["New policy"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Policy #")).firstMatch.waitForExistence(timeout: 10))
        snapshot("policies-wallet")

        // Issue flow.
        app.buttons["New policy"].tap()
        XCTAssertTrue(app.buttons["Oceanic Shipping Corp"].waitForExistence(timeout: 5))
        app.buttons["Oceanic Shipping Corp"].tap()
        snapshot("issue-1-client")
        app.buttons["Next"].tap()

        XCTAssertTrue(app.buttons["Hull & Machinery"].waitForExistence(timeout: 5))
        snapshot("issue-2-type")
        app.buttons["Next"].tap()

        XCTAssertTrue(app.buttons["Ever Pioneer"].waitForExistence(timeout: 5))
        app.buttons["Ever Pioneer"].tap()
        snapshot("issue-3-vessel")
        app.buttons["Next"].tap()

        // Random slider positions give unique amounts.
        let sumSlider = app.sliders["Sum insured"]
        XCTAssertTrue(sumSlider.waitForExistence(timeout: 5))
        sumSlider.adjust(toNormalizedSliderPosition: CGFloat.random(in: 0.35...0.75))
        app.sliders["Premium"].adjust(toNormalizedSliderPosition: CGFloat.random(in: 0.25...0.6))
        snapshot("issue-4-amounts")
        app.buttons["Next"].tap()

        XCTAssertTrue(app.buttons["Cover ends"].waitForExistence(timeout: 5))
        snapshot("issue-5-dates")
        app.buttons["Next"].tap()

        XCTAssertTrue(app.buttons["Apex Maritime Brokers Ltd"].waitForExistence(timeout: 5))
        app.buttons["Apex Maritime Brokers Ltd"].tap()
        app.buttons["James Montgomery"].tap()
        snapshot("issue-6-parties")
        app.buttons["Next"].tap()

        let reviewSum = app.descendants(matching: .any)["review-sum-insured"]
        XCTAssertTrue(reviewSum.waitForExistence(timeout: 5))
        let sumInsured = digits(reviewSum.value as? String)
        let premium = digits(app.descendants(matching: .any)["review-premium"].value as? String)
        snapshot("issue-7-review")
        app.buttons["Save as draft"].tap()

        // The new policy's screen opens.
        let number = app.staticTexts["policy-number"]
        XCTAssertTrue(number.waitForExistence(timeout: 10))
        let policyNo = try XCTUnwrap(Int(number.label.replacingOccurrences(of: "Policy #", with: "")))
        addTeardownBlock { await Self.deleteOnServer("policies/\(policyNo)") }

        let created = try await serverObject("policies/\(policyNo)")
        XCTAssertEqual(created?["status"] as? String, "DRAFT")
        XCTAssertEqual(created?["policy_type"] as? String, "HULL")
        XCTAssertEqual(created?["client_id"] as? Int, 1)
        XCTAssertEqual(created?["vessel_id"] as? Int, 1)
        XCTAssertEqual(created?["broker_id"] as? Int, 1)
        XCTAssertEqual(created?["emp_id"] as? Int, 1)
        XCTAssertEqual(decimal(created?["sum_insured"]), Decimal(string: sumInsured))
        XCTAssertEqual(decimal(created?["premium"]), Decimal(string: premium))
        XCTAssertEqual(decimal(created?["vessel_value_covered"]), Decimal(string: sumInsured))

        // Quote, then bind.
        XCTAssertTrue(app.buttons["Quote"].waitForExistence(timeout: 5))
        app.buttons["Quote"].tap()
        XCTAssertTrue(app.buttons["Bind"].waitForExistence(timeout: 5))
        let quotedStatus = try await serverStatus(policyNo, becomes: "QUOTED")
        XCTAssertEqual(quotedStatus, "QUOTED")
        snapshot("policy-detail-quoted")

        app.buttons["Bind"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["bound-seal"].waitForExistence(timeout: 5))
        let boundStatus = try await serverStatus(policyNo, becomes: "BOUND")
        XCTAssertEqual(boundStatus, "BOUND")
        snapshot("policy-detail-top")

        app.swipeUp()
        snapshot("policy-detail-web")

        // Reinsurance shares: 20% each when added, then +5% on the first.
        let editShares = app.buttons["Edit shares"]
        if !editShares.isHittable { app.swipeUp() }
        editShares.tap()
        XCTAssertTrue(app.buttons["Swiss Marine Reinsurance AG"].waitForExistence(timeout: 5))
        app.buttons["Swiss Marine Reinsurance AG"].tap()
        app.buttons["Munich Global Re"].tap()
        let increase = app.buttons["Increase Swiss Marine Reinsurance AG share"]
        XCTAssertTrue(increase.waitForExistence(timeout: 5))
        for _ in 0..<5 { increase.tap() }
        snapshot("reinsurance-builder")
        app.buttons["Save"].tap()
        XCTAssertTrue(editShares.waitForExistence(timeout: 10))

        let shares = try await serverArray("reinsured-by/?policy_no=\(policyNo)")
        let byReinsurer = Dictionary(uniqueKeysWithValues: shares.map { ($0["reinsurer_id"] as? Int ?? 0, decimal($0["share_percent"])) })
        XCTAssertEqual(byReinsurer, [1: 25, 2: 20])
        snapshot("policy-detail-reinsurance")

        // Delete.
        app.buttons["Delete"].tap()
        snapshot("policy-delete-dialog")
        app.buttons["Delete policy"].tap()
        XCTAssertTrue(app.buttons["New policy"].waitForExistence(timeout: 10))
        let (status, _) = try await Self.server("policies/\(policyNo)")
        XCTAssertEqual(status, 404)
        let orphanShares = try await serverArray("reinsured-by/?policy_no=\(policyNo)")
        XCTAssertTrue(orphanShares.isEmpty)
    }

    @MainActor func testFiltersAndRelationshipWeb() {
        app.launch()
        app.tabBars.buttons["Policies"].tap()
        XCTAssertTrue(app.buttons["Cargo"].waitForExistence(timeout: 10))
        app.buttons["Cargo"].tap()
        let cargoCard = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Cargo Transit")).firstMatch
        XCTAssertTrue(cargoCard.waitForExistence(timeout: 5))
        snapshot("policies-filter-cargo")
        app.buttons["All"].tap()

        // Seed policy #1 links a client, broker, underwriter, vessel, two reinsurers and a claim.
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Policy #1,")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        XCTAssertTrue(app.staticTexts["policy-number"].waitForExistence(timeout: 5))
        app.swipeUp()
        let clientNode = app.buttons["Client: Oceanic Shipping Corp"]
        XCTAssertTrue(clientNode.waitForExistence(timeout: 5))
        snapshot("policy-seed-web")
        clientNode.tap()
        XCTAssertTrue(app.staticTexts["Oceanic Shipping Corp"].waitForExistence(timeout: 5))
    }

    /// The Bridge "New policy" button opens the flow, and a client added from inside it is picked.
    @MainActor func testNewPolicyFromBridgeAddsClientInline() async throws {
        let name = "Inline Client \(Int.random(in: 1000...9999))"
        addTeardownBlock {
            let clients = try? await Self.server("clients/").1 as? [[String: Any]]
            for client in clients ?? [] where client["name"] as? String == name {
                await Self.deleteOnServer("clients/\(client["client_id"] ?? 0)")
            }
        }
        app.launch()
        XCTAssertTrue(app.buttons["New policy"].waitForExistence(timeout: 10))
        app.buttons["New policy"].tap()

        app.buttons["Add a new client"].tap()
        let field = app.textFields["Name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.buttons["Add"].tap()

        let card = app.buttons[name]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.isSelected)
        XCTAssertTrue(app.buttons["Next"].isEnabled)
        snapshot("issue-inline-client")
        app.buttons["Close"].tap()
    }

    // MARK: - Helpers

    private func digits(_ text: String?) -> String {
        (text ?? "").filter(\.isNumber)
    }

    private func decimal(_ value: Any?) -> Decimal? {
        (value as? String).flatMap { Decimal(string: $0) }
    }

    private static func server(_ path: String, method: String = "GET") async throws -> (Int, Any?) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8000/api/\(path)")!)
        request.httpMethod = method
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, try? JSONSerialization.jsonObject(with: data))
    }

    private func serverObject(_ path: String) async throws -> [String: Any]? {
        try await Self.server(path).1 as? [String: Any]
    }

    private func serverArray(_ path: String) async throws -> [[String: Any]] {
        try await Self.server(path).1 as? [[String: Any]] ?? []
    }

    /// Polls until the policy reaches `status` (or 10 seconds pass) and returns the last status seen.
    private func serverStatus(_ policyNo: Int, becomes status: String) async throws -> String? {
        var last: String?
        for _ in 0..<20 {
            last = try await serverObject("policies/\(policyNo)")?["status"] as? String
            if last == status { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        return last
    }

    /// Cleanup if the test stops early. A 404 here just means the test already deleted it.
    private static func deleteOnServer(_ path: String) async {
        _ = try? await server(path, method: "DELETE")
    }

    /// Saves a screenshot when SCREENSHOT_DIR is set (pass TEST_RUNNER_SCREENSHOT_DIR to xcodebuild).
    @MainActor private func snapshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        add(XCTAttachment(screenshot: screenshot))
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else { return }
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
