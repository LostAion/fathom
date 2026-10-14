import Charts
import SwiftUI

/// Claimed amount as a bar against the policy's sum insured.
struct ExposureBar: View {
    let amount: Decimal
    let limit: Decimal?
    let tint: Color

    var body: some View {
        let fraction = limit.map { $0 > 0 ? min(1, max(0, ratio(amount, $0))) : 0 } ?? 0
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.inkMuted.opacity(0.18))
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(6, proxy.size.width * fraction))
                }
            }
            .frame(height: 8)
            HStack {
                Text(amount.money)
                    .font(.rounded(.subheadline, weight: .semibold))
                    .contentTransition(.numericText())
                Spacer()
                if let limit {
                    Text("of \(limit.compactMoney) insured")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Claimed \(amount.money)")
        .accessibilityValue(limit.map { "\(Int((fraction * 100).rounded())) percent of \($0.money) insured" } ?? "")
    }
}

func ratio(_ a: Decimal, _ b: Decimal) -> Double {
    NSDecimalNumber(decimal: a / b).doubleValue
}

/// Overlapping monograms for the surveyors on a claim.
struct SurveyorStack: View {
    let names: [String]
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(names.prefix(4).enumerated()), id: \.offset) { _, name in
                Monogram(name: name, tint: NetworkKind.surveyor.tint, size: size)
                    .background(Theme.abyss, in: .circle)
            }
            if names.count > 4 {
                Text("+\(names.count - 4)")
                    .font(.caption2.weight(.bold))
                    .padding(.leading, size * 0.4)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(names.isEmpty ? "No surveyor" : "Surveyors: \(names.joined(separator: ", "))")
    }
}

/// Reported → Under survey → Settled or Rejected, with the current step lit.
struct ClaimTimeline: View {
    let status: ClaimStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stops: [(label: String, symbol: String, tint: Color)] {
        let last: (String, String, Color) = switch status {
        case .settled: (ClaimStatus.settled.label, "checkmark.seal.fill", ClaimStatus.settled.tint)
        case .rejected: (ClaimStatus.rejected.label, "xmark.seal.fill", ClaimStatus.rejected.tint)
        default: ("Settled or rejected", "seal", Theme.inkMuted)
        }
        return [
            (ClaimStatus.reported.label, "exclamationmark.bubble.fill", ClaimStatus.reported.tint),
            (ClaimStatus.underSurvey.label, "magnifyingglass", ClaimStatus.underSurvey.tint),
            last,
        ]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                let reached = index <= status.step
                let current = index == status.step
                VStack(spacing: 8) {
                    Image(systemName: stop.symbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(reached ? stop.tint : Theme.inkMuted.opacity(0.6))
                        .frame(width: 44, height: 44)
                        .background((reached ? stop.tint : Theme.inkMuted).opacity(current ? 0.22 : 0.1), in: .circle)
                        .overlay {
                            Circle().strokeBorder(stop.tint.opacity(current ? 0.9 : 0), lineWidth: 2)
                        }
                        .symbolEffect(.pulse, isActive: current && status.isOpen && !reduceMotion)
                    Text(stop.label)
                        .font(.caption.weight(current ? .bold : .regular))
                        .foregroundStyle(current ? Theme.ink : Theme.inkMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(stop.label)
                .accessibilityValue(current ? "Current step" : reached ? "Done" : "Not reached")
            }
        }
        .background(alignment: .topLeading) { connectors }
    }

    /// Lines between the step circles, lit up to the current step.
    private var connectors: some View {
        GeometryReader { proxy in
            let segment = proxy.size.width / CGFloat(stops.count)
            HStack(spacing: 0) {
                ForEach(1..<stops.count, id: \.self) { index in
                    Capsule()
                        .fill(index <= status.step ? stops[index].tint.opacity(0.7) : Theme.inkMuted.opacity(0.25))
                        .frame(width: max(0, segment - 56), height: 3)
                        .frame(width: segment)
                }
            }
            .offset(x: segment / 2, y: 20.5)
        }
        .accessibilityHidden(true)
    }
}

/// Claim → deductible → aggregate limit → payout, drawn as a horizontal waterfall.
struct PayoutWaterfall: View {
    let estimate: PayoutEstimate
    /// Draws the remaining aggregate limit as a dashed line when it caps the claim.
    var marksLimit = true

    private struct Bar: Identifiable {
        let label: String
        let from: Decimal
        let to: Decimal
        let tint: Color
        var id: String { label }
    }

    private var bars: [Bar] {
        var bars = [Bar(label: "Claim", from: 0, to: estimate.claimAmount, tint: Theme.coral),
                    Bar(label: "Deductible", from: estimate.afterDeductible, to: estimate.claimAmount, tint: Theme.amber)]
        if estimate.limitCut > 0 {
            bars.append(Bar(label: "Over limit", from: estimate.payout, to: estimate.afterDeductible, tint: Theme.lavender))
        }
        bars.append(Bar(label: "Payout", from: 0, to: estimate.payout, tint: Theme.teal))
        return bars
    }

    var body: some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(
                    xStart: .value("From", double(bar.from)),
                    xEnd: .value("To", double(bar.to)),
                    y: .value("Step", bar.label)
                )
                .foregroundStyle(bar.tint.gradient)
                .clipShape(.rect(cornerRadius: 6))
            }
            if marksLimit && estimate.remainingLimit < estimate.claimAmount {
                RuleMark(x: .value("Limit left", double(estimate.remainingLimit)))
                    .foregroundStyle(Theme.lavender)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Limit left")
                            .font(.caption2)
                            .foregroundStyle(Theme.lavender)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.inkMuted.opacity(0.2))
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(Decimal(amount).compactMoney)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel().foregroundStyle(Theme.inkMuted)
            }
        }
        .frame(minHeight: CGFloat(bars.count) * 34)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Payout breakdown")
        .accessibilityValue("Claim \(estimate.claimAmount.money), minus deductible \(estimate.deductibleCut.money)"
            + (estimate.limitCut > 0 ? ", minus \(estimate.limitCut.money) over the remaining limit" : "")
            + ", payout \(estimate.payout.money)")
    }

    private func double(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }
}

/// A label and an amount on one line, used in breakdowns.
struct AmountLine: View {
    let label: String
    let amount: Decimal
    var sign = ""
    var tint: Color = Theme.ink
    var emphasised = false

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(emphasised ? Theme.ink : Theme.inkMuted)
            Spacer()
            Text(sign + amount.money)
                .font(.rounded(emphasised ? .title3 : .body, weight: emphasised ? .bold : .medium))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
        }
        .font(emphasised ? .headline : .subheadline)
        .accessibilityElement(children: .combine)
    }
}

/// The policy's coverage period as a bar with the loss date marked on it.
struct CoverageStrip: View {
    let issueDay: String?
    let expiryDay: String?
    let lossDay: String

    var body: some View {
        let check = CoverageCheck(lossDay: lossDay, issueDay: issueDay, expiryDay: expiryDay)
        let tint = check.isCovered ? Theme.teal : Theme.coral
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let x = proxy.size.width * position
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.teal.opacity(0.25)).frame(height: 10)
                    Circle()
                        .fill(tint)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Theme.abyss, lineWidth: 3))
                        .offset(x: min(max(0, x - 9), proxy.size.width - 18))
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 20)
            HStack {
                Text(APIDate.parse(issueDay)?.dayText ?? "Open start")
                Spacer()
                Text(APIDate.parse(expiryDay)?.dayText ?? "Open end")
            }
            .font(.caption)
            .foregroundStyle(Theme.inkMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coverage period")
        .accessibilityValue("\(APIDate.parse(issueDay)?.dayText ?? "open") to \(APIDate.parse(expiryDay)?.dayText ?? "open"). Loss date \(check.isCovered ? "inside" : "outside") it.")
    }

    /// Where the loss falls along the bar, 0...1, pinned to the ends when outside.
    private var position: Double {
        guard let start = APIDate.parse(issueDay), let end = APIDate.parse(expiryDay),
              let loss = APIDate.parse(lossDay), end > start else { return 0.5 }
        return min(1, max(0, loss.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }
}

// MARK: - Bindings

extension Binding where Value == String? {
    /// Edits a "yyyy-MM-dd" column with a DatePicker. Use with `.environment(\.timeZone, .gmt)`.
    func day(default fallback: String) -> Binding<Date> {
        Binding<Date>(
            get: { APIDate.parse(wrappedValue) ?? APIDate.parse(fallback) ?? .now },
            set: { wrappedValue = APIDate.string($0) }
        )
    }

    /// Edits a decimal string column as a number.
    var decimalValue: Binding<Decimal> {
        Binding<Decimal>(
            get: { Decimal(apiString: wrappedValue) ?? 0 },
            set: { wrappedValue = $0.apiString }
        )
    }
}
