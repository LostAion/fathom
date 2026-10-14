import XCTest

/// Drives the Fleet tab against a running backend: adds a vessel, plots a voyage with cargo,
/// checks the rows on the server, opens the detail screens and cleans up.
/// Needs the API at http://127.0.0.1:8000 with seed data loaded.
final class FleetUITests: XCTestCase {
    @MainActor private var app: XCUIApplication { XCUIApplication() }
    private static let api = "http://127.0.0.1:8000/api"
    private let seedCargo = "Containerized Consumer Electronics"

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor func testPlotVoyageEndToEnd() async throws {
        let suffix = Int.random(in: 1000...9999)
        let vesselName = "Test Mariner \(suffix)"
        addTeardownBlock { await Self.removeLeftovers(vesselName: vesselName) }
        app.launch()

        // Map and panel segments.
        app.tabBars.buttons["Fleet"].tap()
        let everPioneer = element(beginningWith: "Ever Pioneer")
        XCTAssertTrue(everPioneer.waitForExistence(timeout: 15))
        settle()
        snapshot("fleet-vessels")
        app.buttons["Collapse panel"].tap()
        settle()
        snapshot("fleet-map")
        app.buttons["Expand panel"].tap()
        settle()

        // Add a vessel through the sheet.
        app.buttons["Add vessel"].tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(vesselName)
        app.textFields["IMO number"].tap()
        app.textFields["IMO number"].typeText("IMO7\(suffix)00")
        app.textFields["Tonnage"].tap()
        app.textFields["Tonnage"].typeText("54000")
        element(beginningWith: "Flag").tap()
        let panama = element(containing: "Panama")
        XCTAssertTrue(panama.waitForExistence(timeout: 5))
        panama.tap()
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 5))
        snapshot("vessel-add-sheet")
        app.buttons["Add"].tap()
        XCTAssertTrue(element(beginningWith: vesselName).waitForExistence(timeout: 5))
        let vessels = await Self.serverRows("vessels/")
        let vessel = try XCTUnwrap(vessels.first { $0["name"] as? String == vesselName })
        XCTAssertEqual(vessel["flag"] as? String, "Panama")
        XCTAssertEqual(vessel["tonnage"] as? Int, 54000)
        let vesselId = try XCTUnwrap(vessel["vessel_id"] as? Int)

        app.buttons["Voyages"].tap()
        XCTAssertTrue(app.buttons["Plot voyage"].waitForExistence(timeout: 5))
        settle()
        snapshot("fleet-voyages")
        app.buttons["Cargo"].tap()
        XCTAssertTrue(element(containing: seedCargo).waitForExistence(timeout: 5))
        snapshot("fleet-cargo")
        app.buttons["Voyages"].tap()

        // Plot Voyage flow.
        app.buttons["Plot voyage"].tap()
        let search = app.textFields["Port search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        settle()
        snapshot("plot-1-origin")
        search.tap()
        search.typeText("Rotter")
        app.buttons["port-Rotterdam"].tap()
        next()

        search.tap()
        search.typeText("Singa")
        app.buttons["port-Singapore"].tap()
        XCTAssertTrue(element(containing: "Distance").waitForExistence(timeout: 15))
        settle(3)
        snapshot("plot-2-destination")
        next()

        XCTAssertTrue(app.sliders.firstMatch.waitForExistence(timeout: 5))
        snapshot("plot-3-speed")
        next()

        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        snapshot("plot-4-departure")
        next()

        let card = element(beginningWith: vesselName)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        for _ in 0..<6 where !card.isHittable {
            app.scrollViews["Vessel picker"].swipeLeft()
        }
        card.tap()
        snapshot("plot-5-vessel")
        next()

        app.buttons[seedCargo].tap()
        snapshot("plot-6-cargo")
        next()

        XCTAssertTrue(app.buttons["Finish plot"].waitForExistence(timeout: 5))
        snapshot("plot-7-review")
        app.buttons["Finish plot"].tap()

        // The server has the voyage and its carries row.
        let open = app.buttons["Open voyage"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        let voyages = await Self.serverRows("voyages/?vessel_id=\(vesselId)")
        let voyage = try XCTUnwrap(voyages.first)
        XCTAssertEqual(voyage["origin_port"] as? String, "Rotterdam")
        XCTAssertEqual(voyage["dest_port"] as? String, "Singapore")
        let voyageId = try XCTUnwrap(voyage["voyage_id"] as? Int)
        let cargos = await Self.serverRows("cargos/")
        let cargoId = try XCTUnwrap(cargos.first { $0["description"] as? String == seedCargo }?["cargo_id"] as? Int)
        let carries = await Self.serverRows("carries/?voyage_id=\(voyageId)")
        XCTAssertEqual(carries.compactMap { $0["cargo_id"] as? Int }, [cargoId])
        settle()
        snapshot("fleet-voyage-focused")

        // Voyage detail shows the sea-lane distance (about 8,400 nm).
        open.tap()
        let distance = element(containing: "via sea lanes")
        XCTAssertTrue(distance.waitForExistence(timeout: 10))
        let miles = Int(distance.label.filter(\.isNumber).prefix(5)) ?? 0
        XCTAssertTrue((8_200...8_500).contains(miles), "Distance label was \(distance.label)")
        settle()
        snapshot("voyage-detail")

        element(beginningWith: vesselName).tap()
        XCTAssertTrue(element(containing: "IMO number").waitForExistence(timeout: 5))
        snapshot("vessel-detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        element(containing: seedCargo).firstMatch.tap()
        XCTAssertTrue(element(containing: "Declared value").waitForExistence(timeout: 5))
        snapshot("cargo-detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Delete the voyage; its carries row goes with it (CASCADE).
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
        app.buttons["Delete"].tap()
        snapshot("voyage-delete-dialog")
        app.buttons["Delete voyage"].tap()
        XCTAssertTrue(app.buttons["Plot voyage"].waitForExistence(timeout: 10))
        let voyagesLeft = await Self.serverRows("voyages/?vessel_id=\(vesselId)")
        XCTAssertTrue(voyagesLeft.isEmpty)
        let carriesLeft = await Self.serverRows("carries/?voyage_id=\(voyageId)")
        XCTAssertTrue(carriesLeft.isEmpty)

        // Delete the vessel from its passport.
        app.buttons["Vessels"].tap()
        let passport = element(beginningWith: vesselName)
        XCTAssertTrue(passport.waitForExistence(timeout: 5))
        for _ in 0..<8 where !passport.isHittable {
            app.scrollViews["Vessel carousel"].swipeLeft()
        }
        passport.tap()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
        app.buttons["Delete"].tap()
        app.buttons["Delete vessel"].tap()
        XCTAssertTrue(everPioneer.waitForExistence(timeout: 10))
        let vesselLeft = await Self.serverRows("vessels/").first { $0["vessel_id"] as? Int == vesselId }
        XCTAssertNil(vesselLeft)
    }

    // MARK: - Helpers

    @MainActor private func element(beginningWith text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    @MainActor private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor private func next() {
        let button = app.buttons["Next step"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    /// Lets map tiles and animations finish before a screenshot.
    private func settle(_ seconds: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private static func serverRows(_ path: String) async -> [[String: Any]] {
        let separator = path.contains("?") ? "&" : "?"
        guard let url = URL(string: "\(api)/\(path)\(separator)limit=500"),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
    }

    /// Deletes anything this test created if it stopped part way.
    private static func removeLeftovers(vesselName: String) async {
        guard let vessel = await serverRows("vessels/").first(where: { $0["name"] as? String == vesselName }),
              let id = vessel["vessel_id"] as? Int else { return }
        for voyage in await serverRows("voyages/?vessel_id=\(id)") {
            if let voyageId = voyage["voyage_id"] as? Int { await send("DELETE", "voyages/\(voyageId)") }
        }
        await send("DELETE", "vessels/\(id)")
    }

    private static func send(_ method: String, _ path: String) async {
        var request = URLRequest(url: URL(string: "\(api)/\(path)")!)
        request.httpMethod = method
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Saves a screenshot when SCREENSHOT_DIR is set (pass TEST_RUNNER_SCREENSHOT_DIR to xcodebuild).
    @MainActor private func snapshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        add(XCTAttachment(screenshot: screenshot))
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else { return }
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
