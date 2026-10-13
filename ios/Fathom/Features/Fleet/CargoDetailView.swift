import SwiftUI

/// Placeholder until this screen is built.
struct CargoDetailView: View {
    let cargoId: Int

    var body: some View {
        ContentUnavailableView("Cargo #\(cargoId)", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            .background { SonarBackground() }
    }
}
