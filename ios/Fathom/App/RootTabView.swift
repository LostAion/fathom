import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Bridge", systemImage: "gauge.with.dots.needle.33percent") {
                BridgeView()
            }
            Tab("Fleet", systemImage: "map") {
                FleetView()
            }
            Tab("Policies", systemImage: "shield.lefthalf.filled") {
                PoliciesView()
            }
            Tab("Claims", systemImage: "lifepreserver") {
                ClaimsView()
            }
            Tab("Network", systemImage: "person.3") {
                NetworkView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Theme.teal)
    }
}

#Preview {
    RootTabView()
        .environment(ConnectionMonitor())
        .environment(Ledger())
        .environment(SeaRoutes())
}
