import MapKit
import SwiftUI

/// Finds coordinates for a stored port name. Names from the bundled catalog resolve
/// at once; anything else (typed in through the API) is looked up with MapKit search.
@Observable
final class PortLocator {
    static let shared = PortLocator()

    private var found: [String: Port] = [:]
    private var searched: Set<String> = []

    func port(named name: String?) -> Port? {
        PortCatalog.named(name) ?? name.flatMap { found[Self.key($0)] }
    }

    func locate(_ name: String?) async {
        guard let name, !name.isBlank, port(named: name) == nil, !searched.contains(Self.key(name)) else { return }
        searched.insert(Self.key(name))
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return }
        let coordinate = item.location.coordinate
        found[Self.key(name)] = Port(name: name, locode: "geo:\(Self.key(name))", country: "",
                                     latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private static func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespaces).lowercased() }
}

extension Port {
    /// Catalog ports carry a country code; looked-up ones get a plain pin instead.
    var flagOrPin: String { country.isEmpty ? "📍" : flag }
}

/// The line a voyage follows: the real sea lane once loaded, otherwise a great-circle arc.
struct VoyageTrack {
    var path: [CLLocationCoordinate2D]
    var distanceNm: Double
    var isSeaLane: Bool

    var distanceText: String { "\(Int(distanceNm.rounded()).formatted()) nm" }
}

extension SeaRoutes {
    func track(from origin: Port, to destination: Port) -> VoyageTrack {
        if let route = cached(from: origin, to: destination) {
            return VoyageTrack(path: RouteGeometry.unwrapped(route.path), distanceNm: route.distanceNm, isSeaLane: true)
        }
        return VoyageTrack(path: RouteGeometry.geodesic(from: origin.coordinate, to: destination.coordinate),
                           distanceNm: RouteGeometry.distanceNm(origin.coordinate, destination.coordinate),
                           isSeaLane: false)
    }

    /// Resolves both ports and fetches the sea lane. Returns false when the lane
    /// couldn't be loaded, so callers can label the great-circle fallback.
    func chart(_ voyage: Voyage) async -> Bool {
        let locator = PortLocator.shared
        await locator.locate(voyage.originPort)
        await locator.locate(voyage.destPort)
        guard let origin = locator.port(named: voyage.originPort),
              let destination = locator.port(named: voyage.destPort) else { return false }
        return (try? await route(from: origin, to: destination)) != nil
    }
}

/// Everything the map needs to draw one voyage.
struct VoyagePlot: Identifiable {
    let voyage: Voyage
    let origin: Port
    let destination: Port
    let track: VoyageTrack
    let passage: Passage?
    let state: VoyageState
    let progress: Double

    var id: Int { voyage.id }
    var ship: CLLocationCoordinate2D {
        RouteGeometry.normalized(RouteGeometry.point(along: track.path, fraction: progress) ?? origin.coordinate)
    }
    var heading: Double { RouteGeometry.heading(along: track.path, fraction: progress) }
    var segments: [RouteSegment] {
        RouteGeometry.mapSegments(track.path).enumerated().map { RouteSegment(id: "\(id)-\($0.offset)", path: $0.element) }
    }

    /// Bounds of the route for fitting the camera; unwrapped so Pacific crossings stay compact.
    var rect: MKMapRect {
        track.path.map(MKMapPoint.init).reduce(MKMapRect.null) {
            $0.union(MKMapRect(origin: $1, size: MKMapSize(width: 1, height: 1)))
        }
    }

    static func make(_ voyage: Voyage, seaRoutes: SeaRoutes, now: Date) -> VoyagePlot? {
        let locator = PortLocator.shared
        guard let origin = locator.port(named: voyage.originPort),
              let destination = locator.port(named: voyage.destPort) else { return nil }
        let track = seaRoutes.track(from: origin, to: destination)
        let passage = voyage.departs.map { Passage(depart: $0, distanceNm: track.distanceNm) }
        return VoyagePlot(voyage: voyage, origin: origin, destination: destination, track: track,
                          passage: passage,
                          state: passage?.state(at: now) ?? .scheduled,
                          progress: passage?.progress(at: now) ?? 0)
    }
}

struct RouteSegment: Identifiable {
    let id: String
    let path: [CLLocationCoordinate2D]
}

extension VoyageState {
    /// Amber for pending, teal for underway, muted once she's in.
    var tint: Color {
        switch self {
        case .scheduled: Theme.amber
        case .atSea: Theme.teal
        case .arrived: Theme.inkMuted
        }
    }

    var symbol: String {
        switch self {
        case .scheduled: "calendar"
        case .atSea: "water.waves"
        case .arrived: "checkmark.seal.fill"
        }
    }
}

extension MapCameraPosition {
    /// Fits a route with a margin around it.
    static func fitting(_ rect: MKMapRect, padding: Double = 0.15) -> MapCameraPosition {
        .rect(rect.insetBy(dx: -max(rect.size.width, 400_000) * padding, dy: -max(rect.size.height, 400_000) * padding))
    }
}

extension Voyage {
    var routeTitle: String { "\(originPort ?? "Unknown") → \(destPort ?? "Unknown")" }
}

extension Vessel {
    var flagEmoji: String? { FlagState.emoji(for: flag) }
}

extension Policy {
    /// Not cancelled and not past its expiry date.
    var isInForce: Bool {
        lifecycle != .cancelled && (expires ?? .distantFuture) >= Calendar.current.startOfDay(for: .now)
    }
}
