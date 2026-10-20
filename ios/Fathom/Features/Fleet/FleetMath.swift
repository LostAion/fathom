import CoreLocation
import Foundation

/// Distances, positions and headings along a route. Paths may run past ±180° longitude
/// (the sea-route API does this on Pacific crossings), so everything here works on
/// continuous ("unwrapped") longitudes and only normalises when drawing.
nonisolated enum RouteGeometry {
    static let earthRadiusNm = 3440.065

    /// Great-circle distance in nautical miles.
    static func distanceNm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusNm * asin(min(1, sqrt(h)))
    }

    static func length(of path: [CLLocationCoordinate2D]) -> Double {
        zip(path, path.dropFirst()).reduce(0) { $0 + distanceNm($1.0, $1.1) }
    }

    /// The point `fraction` (0...1) of the way along the path, measured by distance.
    static func point(along path: [CLLocationCoordinate2D], fraction: Double) -> CLLocationCoordinate2D? {
        prefix(of: path, fraction: fraction).last
    }

    /// The path cut off at `fraction` of its length, used to draw a route in.
    static func prefix(of path: [CLLocationCoordinate2D], fraction: Double) -> [CLLocationCoordinate2D] {
        guard path.count > 1, fraction < 1 else { return path }
        let target = length(of: path) * max(fraction, 0)
        var result = [path[0]]
        var travelled = 0.0
        for (a, b) in zip(path, path.dropFirst()) {
            let leg = distanceNm(a, b)
            if travelled + leg >= target {
                let t = leg > 0 ? (target - travelled) / leg : 0
                result.append(CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                                     longitude: a.longitude + (b.longitude - a.longitude) * t))
                return result
            }
            result.append(b)
            travelled += leg
        }
        return result
    }

    /// Direction of travel at `fraction`, in degrees clockwise from north on a north-up map.
    static func heading(along path: [CLLocationCoordinate2D], fraction: Double) -> Double {
        let step = 0.01
        guard let a = point(along: path, fraction: max(0, min(fraction, 1 - step))),
              let b = point(along: path, fraction: min(1, max(fraction, 0) + step)) else { return 90 }
        // Mercator y, so the angle matches what the map shows.
        func y(_ lat: Double) -> Double { log(tan(.pi / 4 + lat * .pi / 360)) * 180 / .pi }
        let angle = atan2(b.longitude - a.longitude, y(b.latitude) - y(a.latitude)) * 180 / .pi
        return (angle + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Points on the great circle between two coordinates, with continuous longitudes.
    static func geodesic(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D, points: Int = 64) -> [CLLocationCoordinate2D] {
        func vector(_ c: CLLocationCoordinate2D) -> (Double, Double, Double) {
            let lat = c.latitude * .pi / 180, lon = c.longitude * .pi / 180
            return (cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))
        }
        let p = vector(a), q = vector(b)
        let omega = acos(min(1, max(-1, p.0 * q.0 + p.1 * q.1 + p.2 * q.2)))
        guard omega > 1e-9 else { return [a, b] }
        let path = (0...points).map { i -> CLLocationCoordinate2D in
            let t = Double(i) / Double(points)
            let s1 = sin((1 - t) * omega) / sin(omega), s2 = sin(t * omega) / sin(omega)
            let x = s1 * p.0 + s2 * q.0, y = s1 * p.1 + s2 * q.1, z = s1 * p.2 + s2 * q.2
            return CLLocationCoordinate2D(latitude: atan2(z, sqrt(x * x + y * y)) * 180 / .pi,
                                          longitude: atan2(y, x) * 180 / .pi)
        }
        return unwrapped(path)
    }

    /// Removes jumps of more than 180° between neighbours, so a path never wraps.
    static func unwrapped(_ path: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard var previous = path.first else { return [] }
        var result = [previous]
        for point in path.dropFirst() {
            var lon = point.longitude
            while lon - previous.longitude > 180 { lon -= 360 }
            while lon - previous.longitude < -180 { lon += 360 }
            previous = CLLocationCoordinate2D(latitude: point.latitude, longitude: lon)
            result.append(previous)
        }
        return result
    }

    static func normalized(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        var lon = (c.longitude + 180).truncatingRemainder(dividingBy: 360)
        if lon < 0 { lon += 360 }
        return CLLocationCoordinate2D(latitude: c.latitude, longitude: lon - 180)
    }

    /// Splits a path where it crosses ±180° so each piece can be drawn as a normal map line.
    static func mapSegments(_ path: [CLLocationCoordinate2D]) -> [[CLLocationCoordinate2D]] {
        let path = unwrapped(path)
        guard let first = path.first else { return [] }
        var segments: [[CLLocationCoordinate2D]] = []
        var current = [normalized(first)]
        for (a, b) in zip(path, path.dropFirst()) {
            let na = normalized(a), nb = normalized(b)
            if abs(nb.longitude - na.longitude) > 180 {
                // The leg crosses the antimeridian: end this piece on the edge, start the next on the other side.
                let edge = na.longitude > 0 ? 180.0 : -180.0
                let t = (edge - na.longitude) / (b.longitude - a.longitude)
                let lat = na.latitude + (nb.latitude - na.latitude) * t
                current.append(CLLocationCoordinate2D(latitude: lat, longitude: edge))
                segments.append(current)
                current = [CLLocationCoordinate2D(latitude: lat, longitude: -edge)]
            }
            current.append(nb)
        }
        segments.append(current)
        return segments
    }
}

/// Where a voyage is relative to today.
nonisolated enum VoyageState: CaseIterable {
    case scheduled, atSea, arrived

    var label: String {
        switch self {
        case .scheduled: "Scheduled"
        case .atSea: "At sea"
        case .arrived: "Arrived"
        }
    }

    /// No date counts as scheduled. If the length is unknown we can't tell when she
    /// arrives, so a departed voyage stays "at sea".
    static func classify(depart: Date?, hoursAtSea: Double?, now: Date) -> VoyageState {
        guard let depart, now >= depart else { return .scheduled }
        guard let hoursAtSea else { return .atSea }
        return now < depart.addingTimeInterval(hoursAtSea * 3600) ? .atSea : .arrived
    }
}

/// Timing of one passage. Nothing here is stored: the database only has the ports,
/// the departure date and the vessel.
nonisolated struct Passage {
    /// Speed used for every estimate outside the Plot Voyage flow.
    static let assumedKnots = 14.0

    var depart: Date
    var distanceNm: Double
    var knots = Passage.assumedKnots

    var hours: Double { knots > 0 ? distanceNm / knots : 0 }
    var days: Double { hours / 24 }
    var arrival: Date { depart.addingTimeInterval(hours * 3600) }

    /// Share of the route covered by `now`, clamped to 0...1.
    func progress(at now: Date) -> Double {
        guard hours > 0 else { return now >= depart ? 1 : 0 }
        return min(max(now.timeIntervalSince(depart) / (hours * 3600), 0), 1)
    }

    func state(at now: Date) -> VoyageState {
        VoyageState.classify(depart: depart, hoursAtSea: hours, now: now)
    }
}

/// Vessels store their flag state as a country name ("Panama").
nonisolated enum FlagState {
    private static let english = Locale(identifier: "en_US")

    /// Two-letter country codes with their English names, sorted by name.
    static let countries: [(code: String, name: String)] = Locale.Region.isoRegions
        .map(\.identifier)
        .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
        .compactMap { code in english.localizedString(forRegionCode: code).map { (code, $0) } }
        .sorted { $0.name < $1.name }

    /// Registries most merchant ships fly, shown first in the flag picker.
    /// Built from codes because some names change by OS version ("China mainland").
    static let popular = ["PA", "LR", "MH", "HK", "SG", "MT", "BS", "GR", "CN", "JP", "NO", "GB"]
        .compactMap { english.localizedString(forRegionCode: $0) }

    /// Matches an English or local country name, or a two-letter code.
    static func regionCode(for country: String?) -> String? {
        guard let name = country?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        if name.count == 2, let match = countries.first(where: { $0.code.caseInsensitiveCompare(name) == .orderedSame }) {
            return match.code
        }
        if let match = countries.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return match.code
        }
        return countries.first {
            Locale.current.localizedString(forRegionCode: $0.code)?.caseInsensitiveCompare(name) == .orderedSame
        }?.code
    }

    static func emoji(regionCode code: String) -> String {
        code.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(127_397 + $0.value) }
            .map(String.init)
            .joined()
    }

    static func emoji(for country: String?) -> String? {
        regionCode(for: country).map(emoji(regionCode:))
    }
}
