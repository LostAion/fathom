import CoreLocation
import Foundation
import Testing
@testable import Fathom

struct FleetMathTests {
    private func coord(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // MARK: - Points along a polyline

    @Test func pointAlongEquatorIsProportional() throws {
        // Two equal legs along the equator: 0° → 10° → 20°.
        let path = [coord(0, 0), coord(0, 10), coord(0, 20)]
        let quarter = try #require(RouteGeometry.point(along: path, fraction: 0.25))
        #expect(abs(quarter.longitude - 5) < 1e-6)
        let middle = try #require(RouteGeometry.point(along: path, fraction: 0.5))
        #expect(abs(middle.longitude - 10) < 1e-6)
        let late = try #require(RouteGeometry.point(along: path, fraction: 0.9))
        #expect(abs(late.longitude - 18) < 1e-6)
    }

    @Test func pointClampsToTheEnds() throws {
        let path = [coord(10, 10), coord(20, 30)]
        #expect(try #require(RouteGeometry.point(along: path, fraction: -1)).latitude == 10)
        #expect(try #require(RouteGeometry.point(along: path, fraction: 3)).longitude == 30)
        #expect(RouteGeometry.point(along: [], fraction: 0.5) == nil)
    }

    @Test func pointWeighsLegsByDistance() throws {
        // First leg is three times longer than the second, so halfway lands inside the first.
        let path = [coord(0, 0), coord(0, 30), coord(0, 40)]
        let middle = try #require(RouteGeometry.point(along: path, fraction: 0.5))
        #expect(abs(middle.longitude - 20) < 1e-6)
    }

    @Test func prefixEndsAtTheFraction() {
        let path = [coord(0, 0), coord(0, 10), coord(0, 20)]
        let half = RouteGeometry.prefix(of: path, fraction: 0.5)
        #expect(abs(RouteGeometry.length(of: half) - RouteGeometry.length(of: path) / 2) < 0.01)
        #expect(RouteGeometry.prefix(of: path, fraction: 1).count == 3)
    }

    @Test func oneDegreeOfLatitudeIsSixtyMiles() {
        #expect(abs(RouteGeometry.distanceNm(coord(0, 0), coord(1, 0)) - 60.04) < 0.05)
    }

    @Test func headingFollowsTheRoute() {
        #expect(abs(RouteGeometry.heading(along: [coord(0, 0), coord(0, 10)], fraction: 0.5) - 90) < 0.5)
        #expect(abs(RouteGeometry.heading(along: [coord(0, 0), coord(10, 0)], fraction: 0.5)) < 0.5)
        #expect(abs(RouteGeometry.heading(along: [coord(10, 0), coord(0, 0)], fraction: 0.5) - 180) < 0.5)
    }

    @Test func greatCircleMatchesHaversine() {
        let rotterdam = coord(51.95, 4.05), singapore = coord(1.26, 103.82)
        let arc = RouteGeometry.geodesic(from: rotterdam, to: singapore)
        let direct = RouteGeometry.distanceNm(rotterdam, singapore)
        #expect(abs(RouteGeometry.length(of: arc) - direct) < 1)
        // Roughly 5,700 nm as the crow flies, much shorter than the 8,300+ nm sea lane.
        #expect((5_600...5_800).contains(direct))
    }

    // MARK: - Antimeridian

    @Test func pacificCrossingSplitsIntoTwoSegments() {
        // Sea-route API style: longitudes run past 180.
        let path = [coord(30, 170), coord(32, 190), coord(34, 241)]
        let segments = RouteGeometry.mapSegments(path)
        #expect(segments.count == 2)
        #expect(segments[0].last?.longitude == 180)
        #expect(segments[1].first?.longitude == -180)
        #expect(segments.flatMap { $0 }.allSatisfy { (-180...180).contains($0.longitude) })
        #expect(abs((segments[1].last?.longitude ?? 0) - -119) < 1e-9)
    }

    @Test func unwrapRemovesJumps() {
        let path = RouteGeometry.unwrapped([coord(0, 179), coord(0, -179)])
        #expect(path[1].longitude == 181)
    }

    // MARK: - ETA and state

    @Test func etaAtFourteenKnots() {
        let depart = APIDate.parse("2026-11-01")!
        let passage = Passage(depart: depart, distanceNm: 8_400)
        #expect(passage.hours == 600)
        #expect(passage.days == 25)
        #expect(APIDate.string(passage.arrival) == "2026-11-26")
    }

    @Test func fasterShipArrivesSooner() {
        let depart = APIDate.parse("2026-11-01")!
        let slow = Passage(depart: depart, distanceNm: 4_800, knots: 10)
        let fast = Passage(depart: depart, distanceNm: 4_800, knots: 20)
        #expect(slow.days == 20)
        #expect(fast.days == 10)
        #expect(fast.arrival < slow.arrival)
        #expect(Passage(depart: depart, distanceNm: 100, knots: 0).hours == 0)
    }

    @Test func progressIsClampedToTheRoute() {
        let depart = APIDate.parse("2026-11-01")!
        let passage = Passage(depart: depart, distanceNm: 1_400) // 100 hours
        #expect(passage.progress(at: depart.addingTimeInterval(-3_600)) == 0)
        #expect(abs(passage.progress(at: depart.addingTimeInterval(50 * 3_600)) - 0.5) < 1e-9)
        #expect(passage.progress(at: depart.addingTimeInterval(500 * 3_600)) == 1)
    }

    @Test func voyageStates() {
        let depart = APIDate.parse("2026-11-01")!
        let hours = 100.0
        #expect(VoyageState.classify(depart: depart, hoursAtSea: hours, now: depart.addingTimeInterval(-60)) == .scheduled)
        #expect(VoyageState.classify(depart: depart, hoursAtSea: hours, now: depart) == .atSea)
        #expect(VoyageState.classify(depart: depart, hoursAtSea: hours, now: depart.addingTimeInterval(99 * 3_600)) == .atSea)
        #expect(VoyageState.classify(depart: depart, hoursAtSea: hours, now: depart.addingTimeInterval(100 * 3_600)) == .arrived)
        #expect(VoyageState.classify(depart: nil, hoursAtSea: hours, now: depart) == .scheduled)
        #expect(VoyageState.classify(depart: depart, hoursAtSea: nil, now: depart.addingTimeInterval(1e7)) == .atSea)
    }

    // MARK: - Flags

    @Test(arguments: [("Panama", "🇵🇦"), ("Liberia", "🇱🇷"), ("Singapore", "🇸🇬"), ("marshall islands", "🇲🇭"),
                      ("  Greece ", "🇬🇷"), ("GB", "🇬🇧")])
    func countryNameToFlag(name: String, flag: String) {
        #expect(FlagState.emoji(for: name) == flag)
    }

    @Test func unknownFlagsGiveNothing() {
        #expect(FlagState.emoji(for: "Atlantis") == nil)
        #expect(FlagState.emoji(for: "") == nil)
        #expect(FlagState.emoji(for: nil) == nil)
    }

    @Test func popularRegistriesAreRealCountries() {
        #expect(FlagState.popular.allSatisfy { FlagState.regionCode(for: $0) != nil })
    }
}
