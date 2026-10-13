import SwiftUI

/// Placeholder until this tab is built.
struct ClaimsView: View {
    var body: some View {
        NavigationStack {
            Screen(title: "Claims", subtitle: "Incidents and settlements") {
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
