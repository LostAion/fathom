import CoreLocation
import Foundation

/// A major port from the bundled `ports.json`. Voyages store only the port name
/// (`origin_port` / `dest_port`), so the app looks coordinates up here.
nonisolated struct Port: Codable, Identifiable, Hashable {
    let name: String
    let locode: String
    /// ISO 3166 alpha-2 code.
    let country: String
    let latitude: Double
    let longitude: Double

    var id: String { locode }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    var flag: String {
        country.unicodeScalars
            .compactMap { UnicodeScalar(127_397 + $0.value) }
            .map(String.init)
            .joined()
    }
}

nonisolated enum PortCatalog {
    static let all: [Port] = {
        guard let url = Bundle.main.url(forResource: "ports", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let ports = try? JSONDecoder().decode([Port].self, from: data)
        else { return [] }
        return ports.sorted { $0.name < $1.name }
    }()

    /// Matches a stored port name, ignoring case and surrounding spaces.
    static func named(_ name: String?) -> Port? {
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        return all.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }
}
