import SwiftUI

enum AppTab: Hashable {
    case bridge, fleet, policies, claims, network
}

/// Switches the selected tab, e.g. the Bridge voyage strip opening Fleet. Call it like `openTab(.fleet)`.
struct OpenTabAction {
    var select: (AppTab) -> Void = { _ in }
    func callAsFunction(_ tab: AppTab) { select(tab) }
}

extension EnvironmentValues {
    @Entry var openTab = OpenTabAction()
}

struct RootTabView: View {
    @State private var tab = AppTab.bridge

    var body: some View {
        TabView(selection: $tab) {
            Tab("Bridge", systemImage: "gauge.with.dots.needle.33percent", value: .bridge) {
                BridgeView()
            }
            Tab("Fleet", systemImage: "map", value: .fleet) {
                FleetView()
            }
            Tab("Policies", systemImage: "shield.lefthalf.filled", value: .policies) {
                PoliciesView()
            }
            Tab("Claims", systemImage: "lifepreserver", value: .claims) {
                ClaimsView()
            }
            Tab("Network", systemImage: "person.3", value: .network) {
                NetworkView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Theme.teal)
        .environment(\.openTab, OpenTabAction { tab = $0 })
    }
}

#Preview {
    RootTabView()
        .environment(ConnectionMonitor())
        .environment(Ledger())
        .environment(SeaRoutes())
}
