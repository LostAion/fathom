import SwiftUI

/// Placeholder until this tab is built.
struct PoliciesView: View {
    var body: some View {
        NavigationStack {
            Screen(title: "Policies", subtitle: "Hull, cargo and P&I cover") {
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
