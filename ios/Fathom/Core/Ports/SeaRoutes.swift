import CoreLocation
import Foundation

/// Response of `GET /api/sea-route/`: distance along real shipping lanes and the path.
nonisolated struct SeaRoute: Decodable, Hashable {
    var distanceNm: Double
    /// [longitude, latitude] pairs.
    var coordinates: [[Double]]

    var path: [CLLocationCoordinate2D] {
        coordinates.compactMap { pair in
            pair.count == 2 ? CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0]) : nil
        }
    }

    /// Hours at sea for a given speed.
    func hours(atKnots knots: Double) -> Double {
        knots > 0 ? distanceNm / knots : 0
    }
}

/// Caches routes per port pair so maps and lists don't refetch them.
@Observable
final class SeaRoutes {
    private var cache: [String: SeaRoute] = [:]

    func cached(from origin: Port, to destination: Port) -> SeaRoute? {
        cache[key(origin, destination)]
    }

    func route(from origin: Port, to destination: Port) async throws -> SeaRoute {
        if let hit = cached(from: origin, to: destination) { return hit }
        let route = try await APIClient.shared.seaRoute(from: origin.coordinate, to: destination.coordinate)
        cache[key(origin, destination)] = route
        return route
    }

    private func key(_ a: Port, _ b: Port) -> String { "\(a.locode)-\(b.locode)" }
}
