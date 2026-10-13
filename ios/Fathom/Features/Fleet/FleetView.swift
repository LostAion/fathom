import SwiftUI

/// Placeholder until this tab is built.
struct FleetView: View {
    var body: some View {
        NavigationStack {
            Screen(title: "Fleet", subtitle: "Vessels and voyages") {
                GlassCard {
                    Label("Still being charted", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .appRoutes()
        }
    }
}
