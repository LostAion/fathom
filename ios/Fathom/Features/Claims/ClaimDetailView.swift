import SwiftUI

/// Placeholder until this screen is built.
struct ClaimDetailView: View {
    let claimId: Int

    var body: some View {
        ContentUnavailableView("Claim #\(claimId)", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            .background { SonarBackground() }
    }
}
