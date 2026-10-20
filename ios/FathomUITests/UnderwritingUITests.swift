import XCTest

final class UnderwritingUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor func testAssessRouteRiskAndBind() async throws {
        let vessel = try await create("vessels", ["name": "Underwriting demo", "imo_number": String(UUID().uuidString.prefix(12))])
        let vesselId = try XCTUnwrap(vessel["vessel_id"] as? Int)
        let voyage = try await create("voyages", ["vessel_id": vesselId, "origin_port": "Rotterdam", "dest_port": "Singapore"])
        let voyageId = try XCTUnwrap(voyage["voyage_id"] as? Int)
        let policy = try await create("policies", ["policy_type": "HULL", "sum_insured": "100000", "vessel_id": vesselId])
        let policyNo = try XCTUnwrap(policy["policy_no"] as? Int)
        addTeardownBlock {
            _ = try? await Self.send("DELETE", "policies/\(policyNo)")
            _ = try? await Self.send("DELETE", "voyages/\(voyageId)")
            _ = try? await Self.send("DELETE", "vessels/\(vesselId)")
        }

        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Policies"].tap()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Policy #\(policyNo),")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()
        let assess = app.buttons["assess-risk"]
        scrollTo(assess, in: app)
        assess.tap()
        XCTAssertTrue(app.buttons["Run assessment"].waitForExistence(timeout: 5))
        app.buttons["underwriting-voyage"].tap()
        app.buttons["Rotterdam to Singapore"].tap()
        snapshot("underwriting-inputs")
        app.buttons["Run assessment"].tap()
        let decision = app.staticTexts["underwriting-decision"]
        XCTAssertTrue(decision.waitForExistence(timeout: 10))
        XCTAssertEqual(decision.label, "Approve With Conditions")
        centerAssessment(in: app)
        snapshot("underwriting-result")
        let report = try await Self.send("GET", "policies/\(policyNo)")
        XCTAssertEqual(report["underwriting_decision"] as? String, "APPROVE_WITH_CONDITIONS")
        XCTAssertEqual((report["underwriting_report"] as? [String: Any])?["voyage_id"] as? Int, voyageId)
        let bind = app.buttons["Bind"]
        for _ in 0..<5 where !bind.isHittable { app.swipeDown() }
        XCTAssertTrue(bind.isEnabled)
        bind.tap()
        XCTAssertTrue(app.descendants(matching: .any)["bound-seal"].waitForExistence(timeout: 10))
        snapshot("underwriting-bound")
    }

    @MainActor func testDeclineDisablesBinding() async throws {
        let vessel = try await create("vessels", ["name": "Sanctions fixture", "imo_number": "9135790"])
        let vesselId = try XCTUnwrap(vessel["vessel_id"] as? Int)
        let policy = try await create("policies", ["policy_type": "HULL", "sum_insured": "100000", "vessel_id": vesselId])
        let policyNo = try XCTUnwrap(policy["policy_no"] as? Int)
        addTeardownBlock {
            _ = try? await Self.send("DELETE", "policies/\(policyNo)")
            _ = try? await Self.send("DELETE", "vessels/\(vesselId)")
        }
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Policies"].tap()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Policy #\(policyNo),")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()
        let assess = app.buttons["assess-risk"]
        scrollTo(assess, in: app)
        assess.tap()
        XCTAssertTrue(app.buttons["Run assessment"].waitForExistence(timeout: 5))
        app.buttons["Run assessment"].tap()
        let decision = app.staticTexts["underwriting-decision"]
        XCTAssertTrue(decision.waitForExistence(timeout: 10))
        XCTAssertEqual(decision.label, "Decline")
        centerAssessment(in: app)
        snapshot("underwriting-declined")
        XCTAssertFalse(app.buttons["Bind"].isEnabled)
    }

    @MainActor private func centerAssessment(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(forDuration: 0.1,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    @MainActor private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    private func create(_ resource: String, _ body: [String: Any]) async throws -> [String: Any] {
        try await Self.send("POST", "\(resource)/", body)
    }

    private static func send(_ method: String, _ path: String, _ body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8000/api/\(path)")!)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = try XCTUnwrap((response as? HTTPURLResponse)?.statusCode)
        XCTAssertTrue((200...299).contains(status), "\(method) \(path): \(String(data: data, encoding: .utf8) ?? "")")
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    @MainActor private func snapshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
    }
}
