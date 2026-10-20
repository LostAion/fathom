import SwiftUI

/// Slowly drifting depth contours with a sonar ping, drawn behind every screen.
/// An extra ping runs from the top each time the ledger finishes a reload.
struct SonarBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(Ledger.self) private var ledger: Ledger?
    @State private var refreshPing: Date?

    private let rings = 14
    private let pingPeriod = 6.0

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let center = CGPoint(x: size.width * 0.85, y: size.height * 1.05)
                let maxRadius = hypot(size.width, size.height)

                for ring in 0..<rings {
                    let base = CGFloat(ring + 1) * maxRadius / CGFloat(rings)
                    var path = Path()
                    for step in 0...90 {
                        let angle = Double(step) / 90 * 2 * .pi
                        let wobble = 10 * sin(angle * 3 + Double(ring) * 0.7 + t * 0.15)
                            + 6 * sin(angle * 5 - t * 0.1 + Double(ring))
                        let radius = base + wobble
                        let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                        step == 0 ? path.move(to: point) : path.addLine(to: point)
                    }
                    context.stroke(path, with: .color(Theme.contour), lineWidth: ring % 4 == 0 ? 1.2 : 0.6)
                }

                let phase = t.truncatingRemainder(dividingBy: pingPeriod) / pingPeriod
                let r = phase * maxRadius
                let ping = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
                context.stroke(ping, with: .color(Theme.teal.opacity(0.3 * (1 - phase))), lineWidth: 2)

                if let start = refreshPing?.timeIntervalSinceReferenceDate, t - start < 1.6 {
                    let age = (t - start) / 1.6
                    let origin = CGPoint(x: size.width / 2, y: 0)
                    let r = age * maxRadius * 0.8
                    let sweep = Path(ellipseIn: CGRect(x: origin.x - r, y: origin.y - r, width: 2 * r, height: 2 * r))
                    context.stroke(sweep, with: .color(Theme.teal.opacity(0.5 * (1 - age))), lineWidth: 3)
                }
            }
        }
        .onChange(of: ledger?.refreshes) {
            if !reduceMotion { refreshPing = .now }
        }
        .background(Theme.abyss)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

#Preview {
    SonarBackground()
}
