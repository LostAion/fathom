import SwiftUI

/// Loading indicator: a sounding lead bobbing on a line marked in fathoms.
struct DepthGauge: View {
    var tint = Theme.teal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let depth = reduceMotion ? 0.6 : (sin(t * 2.4) + 1) / 2
            Canvas { context, size in
                let mid = size.width / 2
                let bottom = size.height - 8

                var line = Path()
                line.move(to: CGPoint(x: mid, y: 0))
                line.addLine(to: CGPoint(x: mid, y: 6 + depth * (bottom - 6)))
                context.stroke(line, with: .color(tint.opacity(0.7)), lineWidth: 1.5)

                for mark in 1...5 {
                    let y = bottom * CGFloat(mark) / 6
                    let half: CGFloat = mark.isMultiple(of: 2) ? 7 : 4
                    var tick = Path()
                    tick.move(to: CGPoint(x: mid - half, y: y))
                    tick.addLine(to: CGPoint(x: mid + half, y: y))
                    context.stroke(tick, with: .color(Theme.inkMuted.opacity(0.5)), lineWidth: 1)
                }

                let y = 6 + depth * (bottom - 6)
                var lead = Path()
                lead.move(to: CGPoint(x: mid, y: y - 4))
                lead.addQuadCurve(to: CGPoint(x: mid, y: y + 8), control: CGPoint(x: mid + 9, y: y + 6))
                lead.addQuadCurve(to: CGPoint(x: mid, y: y - 4), control: CGPoint(x: mid - 9, y: y + 6))
                context.fill(lead, with: .color(tint))
            }
        }
        .frame(width: 28, height: 44)
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}

#Preview {
    DepthGauge()
}
