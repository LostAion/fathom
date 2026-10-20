import MapKit
import SwiftUI

// MARK: - Map markers

/// Top-down hull outline, bow pointing up.
nonisolated struct HullShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: w / 2, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: h * 0.42), control: CGPoint(x: w, y: h * 0.12))
        path.addLine(to: CGPoint(x: w * 0.92, y: h))
        path.addLine(to: CGPoint(x: w * 0.08, y: h))
        path.addLine(to: CGPoint(x: 0, y: h * 0.42))
        path.addQuadCurve(to: CGPoint(x: w / 2, y: 0), control: CGPoint(x: 0, y: h * 0.12))
        path.closeSubpath()
        return path
    }
}

/// Ship on the map, turned to her heading, with a soft wake ring when underway.
struct ShipMarker: View {
    let heading: Double
    let tint: Color
    var underway = false
    var size: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            if underway {
                Circle()
                    .stroke(tint.opacity(pulse ? 0 : 0.6), lineWidth: 2)
                    .frame(width: size * 1.8, height: size * 1.8)
                    .scaleEffect(pulse ? 1.4 : 0.7)
            }
            HullShape()
                .fill(tint.gradient)
                .overlay(HullShape().stroke(Theme.abyss, lineWidth: 1.5))
                .frame(width: size * 0.5, height: size)
                .rotationEffect(.degrees(heading))
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        }
        .frame(width: size * 1.8, height: size * 1.8)
        .onAppear {
            guard underway, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// Small port pin with its flag.
struct PortPin: View {
    let port: Port
    var highlighted = false
    var tint = Theme.sky

    var body: some View {
        VStack(spacing: 2) {
            Text(port.flagOrPin)
                .font(.system(size: highlighted ? 20 : 14))
                .frame(width: highlighted ? 34 : 24, height: highlighted ? 34 : 24)
                .background(Theme.abyss.opacity(0.85), in: .circle)
                .overlay(Circle().strokeBorder(highlighted ? tint : Theme.inkMuted.opacity(0.5), lineWidth: highlighted ? 2.5 : 1))
            if highlighted {
                Text(port.name)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.abyss.opacity(0.85), in: .capsule)
                    .fixedSize()
            }
        }
        .animation(.snappy, value: highlighted)
    }
}

// MARK: - Rows

/// "🇳🇱 Rotterdam → 🇸🇬 Singapore" with the state, date and distance under it.
struct VoyageRow: View {
    let voyage: Voyage
    /// Nil until the route has been charted.
    var distance: String?
    var state: VoyageState = .scheduled
    var selected = false

    var body: some View {
        let locator = PortLocator.shared
        let origin = locator.port(named: voyage.originPort)
        let destination = locator.port(named: voyage.destPort)
        HStack(spacing: 14) {
            Image(systemName: state.symbol)
                .font(.title3)
                .foregroundStyle(state.tint)
                .frame(width: 44, height: 44)
                .background(state.tint.opacity(0.15), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("\(origin?.flagOrPin ?? "📍") \(voyage.originPort ?? "Unknown")")
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.inkMuted)
                    Text("\(destination?.flagOrPin ?? "📍") \(voyage.destPort ?? "Unknown")")
                }
                .font(.rounded(.subheadline, weight: .semibold))
                .lineLimit(2)
                Text([voyage.departs.map { "Departs \($0.dayText)" } ?? "No date", distance]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 4)
            StatusChip(text: state.label, tint: state.tint)
        }
        .padding(12)
        .contentShape(.rect)
        .glassEffect(selected ? .regular.tint(state.tint.opacity(0.25)).interactive() : .regular.interactive(),
                     in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(voyage.routeTitle), \(state.label)")
        .accessibilityValue([voyage.departs.map { "departs \($0.dayText)" }, distance].compactMap { $0 }.joined(separator: ", "))
    }
}

struct CargoRow: View {
    let cargo: Cargo
    var detail: String?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "shippingbox.fill")
                .font(.title3)
                .foregroundStyle(Theme.amber)
                .frame(width: 44, height: 44)
                .background(Theme.amber.opacity(0.15), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(cargo.description ?? "Cargo #\(cargo.id)")
                    .font(.rounded(.subheadline, weight: .semibold))
                    .lineLimit(2)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            Spacer(minLength: 4)
            Text(cargo.valueAmount?.compactMoney ?? "–")
                .font(.rounded(.headline, weight: .semibold))
                .contentTransition(.numericText())
        }
        .padding(12)
        .contentShape(.rect)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

struct VesselRow: View {
    let vessel: Vessel
    var detail: String?

    var body: some View {
        HStack(spacing: 14) {
            Text(vessel.flagEmoji ?? "🚢")
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Theme.sky.opacity(0.15), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(vessel.name)
                    .font(.rounded(.headline))
                Text(vessel.imoNumber)
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 4)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
        }
        .padding(12)
        .contentShape(.rect)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Passport

/// A vessel shown as a ship's passport: flag, name, IMO, and a machine-readable strip.
struct PassportCard: View {
    let vessel: Vessel
    let policies: Int
    let voyages: Int
    var selected = false
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: large ? 14 : 10) {
            HStack(alignment: .top) {
                Text(vessel.flagEmoji ?? "🚢")
                    .font(.system(size: large ? 48 : 34))
                    .accessibilityHidden(true)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Ship passport")
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.sky)
                    Text(vessel.flag ?? "No flag")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.teal)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(vessel.name)
                    .font(.rounded(large ? .title : .title3, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(vessel.imoNumber)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(Theme.inkMuted)
            }
            HStack(spacing: 0) {
                stat(vessel.tonnage.map { $0.formatted(.number.notation(.compactName)) } ?? "–", "GT")
                stat("\(policies)", policies == 1 ? "policy" : "policies")
                stat("\(voyages)", voyages == 1 ? "voyage" : "voyages")
            }
            Text(machineStrip)
                .font(.system(size: large ? 11 : 9, design: .monospaced))
                .foregroundStyle(Theme.inkMuted.opacity(0.7))
                .lineLimit(1)
                .accessibilityHidden(true)
        }
        .padding(large ? 20 : 16)
        .frame(width: large ? nil : 250, alignment: .leading)
        .frame(maxWidth: large ? .infinity : nil, alignment: .leading)
        .background(alignment: .bottomTrailing) {
            Image(systemName: "ferry")
                .font(.system(size: large ? 120 : 80))
                .foregroundStyle(Theme.sky.opacity(0.07))
                .offset(x: 12, y: 8)
                .accessibilityHidden(true)
        }
        .clipShape(.rect(cornerRadius: 24))
        .glassEffect(selected ? .regular.tint(Theme.teal.opacity(0.3)).interactive() : .regular.tint(Theme.sky.opacity(0.12)).interactive(),
                     in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(selected ? Theme.teal : Theme.sky.opacity(0.25), lineWidth: selected ? 2 : 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(vessel.name), \(vessel.flag ?? "no flag"), IMO \(vessel.imoNumber)")
        .accessibilityValue("\(counted(policies, "active policy", "active policies")), \(counted(voyages, "voyage"))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.rounded(.headline, weight: .semibold))
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Passport-style "V<PAN<EVER<PIONEER<<<<" line.
    private var machineStrip: String {
        let flag = (FlagState.regionCode(for: vessel.flag) ?? "XX")
        let name = vessel.name.uppercased().map { $0.isLetter || $0.isNumber ? String($0) : "<" }.joined()
        let imo = vessel.imoNumber.uppercased().filter { $0.isLetter || $0.isNumber }
        return String("V<\(flag)<\(name)<<\(imo)<<<<<<<<<<<<<<<<<<<<<<<<<<<<".prefix(44))
    }
}

// MARK: - Facts

struct FleetFact {
    var label: String
    var value: String?
    var monospaced = false
}

struct FactsCard: View {
    let facts: [FleetFact]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                    if index > 0 { Divider() }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fact.label)
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                        Text(fact.value ?? "Not set")
                            .font(fact.monospaced ? .body.monospaced() : .body)
                            .foregroundStyle(fact.value == nil ? Theme.inkMuted : Theme.ink)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Wraps chips onto as many lines as they need.
struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
