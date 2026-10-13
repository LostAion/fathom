import SwiftUI

/// Any record screen one tab can link to from another, e.g. a policy row inside a
/// client profile. Every tab's NavigationStack calls `.appRoutes()`.
enum AppRoute: Hashable {
    case policy(Int)
    case claim(Int)
    case vessel(Int)
    case voyage(Int)
    case cargo(Int)
    case network(NetworkRoute)
}

extension View {
    func appRoutes() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .policy(let no): PolicyDetailView(policyNo: no)
            case .claim(let id): ClaimDetailView(claimId: id)
            case .vessel(let id): VesselDetailView(vesselId: id)
            case .voyage(let id): VoyageDetailView(voyageId: id)
            case .cargo(let id): CargoDetailView(cargoId: id)
            case .network(let route): NetworkProfileView(route: route)
            }
        }
    }
}
