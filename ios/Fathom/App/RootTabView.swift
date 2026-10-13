import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Bridge", systemImage: "gauge.with.dots.needle.33percent") {
                BridgeView()
            }
            Tab("Fleet", systemImage: "map") {
                Screen(title: "Fleet", subtitle: "Vessels and voyages") {
                    ChartingSoon()
                }
            }
            Tab("Policies", systemImage: "shield.lefthalf.filled") {
                Screen(title: "Policies", subtitle: "Hull, cargo and P&I cover") {
                    ChartingSoon()
                }
            }
            Tab("Claims", systemImage: "lifepreserver") {
                Screen(title: "Claims", subtitle: "Incidents and settlements") {
                    ChartingSoon()
                }
            }
            Tab("Network", systemImage: "person.3") {
                NetworkView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Theme.teal)
    }
}

/// Placeholder for tabs that are not built yet.
private struct ChartingSoon: View {
    var body: some View {
        GlassCard {
            Label("Still being charted", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.rounded(.headline))
                .foregroundStyle(Theme.inkMuted)
        }
    }
}

#Preview {
    RootTabView()
        .environment(ConnectionMonitor())
        .environment(Ledger())
}
