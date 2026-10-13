import SwiftUI

/// Placeholder until this screen is built.
struct VoyageDetailView: View {
    let voyageId: Int

    var body: some View {
        ContentUnavailableView("Voyage #\(voyageId)", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            .background { SonarBackground() }
    }
}
