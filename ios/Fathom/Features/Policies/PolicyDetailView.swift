import SwiftUI

/// Placeholder until this screen is built.
struct PolicyDetailView: View {
    let policyNo: Int

    var body: some View {
        ContentUnavailableView("Policy #\(policyNo)", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            .background { SonarBackground() }
    }
}
