import SwiftUI

/// Card art for each policy type, drawn with shapes so it scales and tints cleanly:
/// a ship for hull, stacked containers for cargo, a shield and anchor for P&I.
struct PolicyArt: View {
    let type: PolicyType
    var tint: Color { type.tint }

    var body: some View {
        ZStack {
            switch type {
            case .hull:
                Waves().stroke(tint.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                ShipHull().fill(tint.gradient)
                ShipDeck().fill(tint.opacity(0.65))
            case .cargo:
                ContainerStack(filledRows: true).fill(tint.gradient)
                ContainerStack(filledRows: false).stroke(Theme.abyss.opacity(0.35), lineWidth: 1)
            case .pi:
                Shield().fill(tint.opacity(0.22))
                Shield().stroke(tint.gradient, lineWidth: 2.5)
                Anchor().stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        .aspectRatio(type == .pi ? 0.85 : 1.6, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Shapes

/// Draws in a 0...1 unit square scaled to the rect.
nonisolated private struct Unit {
    let rect: CGRect
    func callAsFunction(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }
    func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
        CGRect(origin: self(x, y), size: CGSize(width: w * rect.width, height: h * rect.height))
    }
}

nonisolated private struct ShipHull: Shape {
    func path(in rect: CGRect) -> Path {
        let u = Unit(rect: rect)
        var path = Path()
        path.move(to: u(0.04, 0.58))
        path.addLine(to: u(0.9, 0.58))
        path.addLine(to: u(0.99, 0.5))
        path.addLine(to: u(0.88, 0.8))
        path.addLine(to: u(0.15, 0.8))
        path.addQuadCurve(to: u(0.04, 0.68), control: u(0.06, 0.8))
        path.closeSubpath()
        return path
    }
}

/// Bridge, funnel and a row of deck containers.
nonisolated private struct ShipDeck: Shape {
    func path(in rect: CGRect) -> Path {
        let u = Unit(rect: rect)
        var path = Path()
        path.addRoundedRect(in: u.box(0.09, 0.3, 0.17, 0.28), cornerSize: CGSize(width: 2, height: 2))
        path.addRect(u.box(0.07, 0.3, 0.22, 0.04))
        path.addRoundedRect(in: u.box(0.14, 0.14, 0.06, 0.16), cornerSize: CGSize(width: 2, height: 2))
        for column in 0..<7 {
            let height = column % 3 == 1 ? 0.18 : 0.12
            path.addRoundedRect(in: u.box(0.31 + Double(column) * 0.08, 0.58 - height, 0.07, height),
                                cornerSize: CGSize(width: 1.5, height: 1.5))
        }
        return path
    }
}

nonisolated private struct Waves: Shape {
    func path(in rect: CGRect) -> Path {
        let u = Unit(rect: rect)
        var path = Path()
        for (row, y) in [0.86, 0.95].enumerated() {
            for step in 0...40 {
                let x = Double(step) / 40
                let point = u(x, y + 0.025 * sin(x * 4 * .pi * 2 + Double(row)))
                step == 0 ? path.move(to: point) : path.addLine(to: point)
            }
        }
        return path
    }
}

/// Containers stacked in a pyramid: 4, then 3, then 2.
nonisolated private struct ContainerStack: Shape {
    /// true for the container bodies, false for the corrugation lines on top.
    let filledRows: Bool

    func path(in rect: CGRect) -> Path {
        let u = Unit(rect: rect)
        var path = Path()
        let width = 0.22, height = 0.25, gap = 0.02
        for (row, count) in [4, 3, 2].enumerated() {
            let rowWidth = Double(count) * width + Double(count - 1) * gap
            let startX = (1 - rowWidth) / 2
            let y = 0.92 - Double(row + 1) * (height + gap)
            for index in 0..<count {
                let x = startX + Double(index) * (width + gap)
                if filledRows {
                    path.addRoundedRect(in: u.box(x, y, width, height), cornerSize: CGSize(width: 2, height: 2))
                } else {
                    for rib in 1..<6 {
                        let ribX = x + width * Double(rib) / 6
                        path.move(to: u(ribX, y + 0.04))
                        path.addLine(to: u(ribX, y + height - 0.04))
                    }
                }
            }
        }
        return path
    }
}

nonisolated private struct Shield: Shape {
    func path(in rect: CGRect) -> Path {
        let u = Unit(rect: rect)
        var path = Path()
        path.move(to: u(0.5, 0.04))
        path.addQuadCurve(to: u(0.94, 0.16), control: u(0.72, 0.16))
        path.addLine(to: u(0.94, 0.5))
        path.addQuadCurve(to: u(0.5, 0.97), control: u(0.92, 0.82))
        path.addQuadCurve(to: u(0.06, 0.5), control: u(0.08, 0.82))
        path.addLine(to: u(0.06, 0.16))
        path.addQuadCurve(to: u(0.5, 0.04), control: u(0.28, 0.16))
        path.closeSubpath()
        return path
    }
}

nonisolated private struct Anchor: Shape {
    func path(in rect: CGRect) -> Path {
        let u = Unit(rect: rect)
        let ringRadius = 0.055 * rect.width
        var path = Path()
        path.addEllipse(in: CGRect(x: u(0.5, 0).x - ringRadius, y: u(0, 0.24).y - ringRadius,
                                   width: ringRadius * 2, height: ringRadius * 2))
        path.move(to: u(0.5, 0.24 + 0.055 * rect.width / rect.height))
        path.addLine(to: u(0.5, 0.8))
        path.move(to: u(0.35, 0.38))
        path.addLine(to: u(0.65, 0.38))
        // Arms: a curve under the shaft ending in two flukes.
        path.move(to: u(0.24, 0.58))
        path.addQuadCurve(to: u(0.5, 0.8), control: u(0.26, 0.8))
        path.addQuadCurve(to: u(0.76, 0.58), control: u(0.74, 0.8))
        path.move(to: u(0.19, 0.64))
        path.addLine(to: u(0.24, 0.58))
        path.addLine(to: u(0.3, 0.63))
        path.move(to: u(0.81, 0.64))
        path.addLine(to: u(0.76, 0.58))
        path.addLine(to: u(0.7, 0.63))
        return path
    }
}

#Preview {
    VStack(spacing: 30) {
        ForEach(PolicyType.allCases) { PolicyArt(type: $0).frame(height: 120) }
    }
    .padding()
    .background(Theme.abyss)
}
