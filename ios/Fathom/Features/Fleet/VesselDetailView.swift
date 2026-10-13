import SwiftUI

/// Placeholder until this screen is built.
struct VesselDetailView: View {
    let vesselId: Int

    var body: some View {
        ContentUnavailableView("Vessel #\(vesselId)", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            .background { SonarBackground() }
    }
}
