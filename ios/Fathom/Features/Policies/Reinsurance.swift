import Charts
import SwiftUI

/// Each reinsurer's share of the policy plus the part the insurer keeps.
struct ReinsuranceDonut: View {
    let links: PolicyLinks

    private struct Slice: Identifiable {
        let id: String
        let name: String
        let percent: Double
        let color: Color
    }

    private var slices: [Slice] {
        var slices = links.shares.enumerated().map { index, share in
            Slice(id: "\(share.reinsurerId)",
                  name: links.reinsurers[share.reinsurerId]?.name ?? "Reinsurer #\(share.reinsurerId)",
                  percent: NSDecimalNumber(decimal: share.share ?? 0).doubleValue,
                  color: ShareColors.reinsurer(index))
        }
        let retained = max(0, 100 - slices.map(\.percent).reduce(0, +))
        if retained > 0 {
            slices.append(Slice(id: "retained", name: "Retained", percent: retained, color: ShareColors.retained))
        }
        return slices
    }

    var body: some View {
        let slices = slices
        VStack(spacing: 16) {
            Chart(slices) { slice in
                SectorMark(angle: .value("Share", slice.percent), innerRadius: .ratio(0.64), angularInset: 1.5)
                    .cornerRadius(4)
                    .foregroundStyle(slice.color)
                    .accessibilityLabel(slice.name)
                    .accessibilityValue(PolicyFormat.percent(Decimal(slice.percent)))
            }
            .chartLegend(.hidden)
            .frame(height: 190)
            .overlay {
                VStack(spacing: 0) {
                    Text(PolicyFormat.percent(links.placedPercent))
                        .font(.rounded(.title2, weight: .bold))
                        .contentTransition(.numericText())
                    Text("placed")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                .accessibilityElement(children: .combine)
            }

            VStack(spacing: 8) {
                ForEach(slices) { slice in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(slice.color)
                            .frame(width: 10, height: 10)
                        Text(slice.name)
                            .font(.subheadline)
                        Spacer(minLength: 8)
                        Text(PolicyFormat.percent(Decimal(slice.percent)))
                            .font(.rounded(.subheadline, weight: .semibold))
                        if let insured = links.policy.sumInsuredAmount {
                            Text((insured * Decimal(slice.percent) / 100).compactMoney)
                                .font(.rounded(.caption))
                                .foregroundStyle(Theme.inkMuted)
                                .frame(minWidth: 52, alignment: .trailing)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Sheet for splitting the policy across reinsurers on one bar. Saving writes only
/// the REINSURED_BY rows that changed.
struct ReinsuranceBuilder: View {
    let policy: Policy

    @Environment(Ledger.self) private var ledger
    @Environment(\.dismiss) private var dismiss
    @State private var split: ShareSplit
    @State private var saving = false
    @State private var error: String?
    @State private var saves = 0

    init(policy: Policy, existing: [ReinsuredBy]) {
        self.policy = policy
        _split = State(initialValue: ShareSplit(existing.map { (reinsurerId: $0.reinsurerId, percent: ShareSplit.wholePercent($0.share)) }))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Pick reinsurers, then drag the dividers to split the risk. Whatever is left is retained.")
                        .font(.callout)
                        .foregroundStyle(Theme.inkMuted)

                    chips

                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            ShareBar(split: $split)
                            summary
                        }
                    }

                    if !split.reinsurerIds.isEmpty {
                        SectionHeader(title: "Shares")
                        ForEach(Array(split.reinsurerIds.enumerated()), id: \.element) { index, id in
                            ShareRow(name: name(of: id), color: ShareColors.reinsurer(index),
                                     percent: split.shares[index], canGrow: split.retained > 0) {
                                split.setShare(index, to: $0)
                            }
                        }
                    }

                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.coral)
                    }
                }
                .padding(20)
            }
            .foregroundStyle(Theme.ink)
            .background { SonarBackground() }
            .navigationTitle("Reinsurance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving)
                }
            }
            .disabled(saving)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: split.shares)
        .sensoryFeedback(.success, trigger: saves)
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(ledger.reinsurers) { reinsurer in
                        let selected = split.reinsurerIds.contains(reinsurer.id)
                        Button {
                            withAnimation(.snappy) {
                                if selected { split.remove(reinsurer.id) } else { split.add(reinsurer.id) }
                            }
                        } label: {
                            Label(reinsurer.name, systemImage: selected ? "checkmark.circle.fill" : "plus.circle")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(selected ? .regular.tint(Theme.lavender.opacity(0.3)).interactive() : .regular.interactive(), in: .capsule)
                        .accessibilityLabel(reinsurer.name)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private var summary: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(split.total)%")
                    .font(.rounded(.title2, weight: .bold))
                    .contentTransition(.numericText(value: Double(split.total)))
                Text("ceded")
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(split.retained)%")
                    .font(.rounded(.title2, weight: .bold))
                    .contentTransition(.numericText(value: Double(split.retained)))
                Text("retained")
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .animation(.snappy, value: split)
        .accessibilityElement(children: .combine)
    }

    private func name(of id: Int) -> String {
        ledger.reinsurers.first { $0.id == id }?.name ?? "Reinsurer #\(id)"
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let changes = split.changes(policyNo: policy.policyNo, existing: ledger.reinsuredBy)
        do {
            for row in changes.delete { try await APIClient.shared.delete(row) }
            for row in changes.update { let _: ReinsuredBy = try await APIClient.shared.update(row) }
            for row in changes.create { let _: ReinsuredBy = try await APIClient.shared.create(row) }
            await ledger.refresh()
            saves += 1
            dismiss()
        } catch {
            self.error = error.localizedDescription
            await ledger.refresh()
        }
    }
}

// MARK: - Pieces

/// One bar split into reinsurer segments plus the retained remainder.
private struct ShareBar: View {
    @Binding var split: ShareSplit

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let edges = split.boundaries
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(ShareColors.retained)
                ForEach(Array(split.shares.enumerated()), id: \.offset) { (index: Int, share: Int) in
                    let start: Int = edges[index] - share
                    let segment: CGFloat = width * CGFloat(share) / 100
                    RoundedRectangle(cornerRadius: 10)
                        .fill(ShareColors.reinsurer(index).gradient)
                        .overlay {
                            if segment > 40 {
                                Text("\(share)%")
                                    .font(.rounded(.caption, weight: .bold))
                                    .foregroundStyle(Theme.abyss)
                            }
                        }
                        .frame(width: max(0, segment - 2), height: height - 8)
                        .offset(x: width * CGFloat(start) / 100 + 1)
                }
            }
        }
        .frame(height: 56)
        .padding(.vertical, 6)
        // Each share row below is adjustable, so the bar itself is just a picture for VoiceOver.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Share bar")
        .accessibilityValue("\(split.total)% ceded, \(split.retained)% retained")
    }
}

/// A reinsurer's share with step buttons. VoiceOver can also swipe up or down on it.
private struct ShareRow: View {
    let name: String
    let color: Color
    let percent: Int
    let canGrow: Bool
    let set: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                Text(name)
                    .font(.rounded(.subheadline, weight: .semibold))
                Spacer(minLength: 8)
                Text("\(percent)%")
                    .font(.rounded(.headline, weight: .bold))
                    .contentTransition(.numericText(value: Double(percent)))
                    .animation(.snappy, value: percent)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name) share")
            .accessibilityValue("\(percent) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: set(percent + 1)
                case .decrement: set(percent - 1)
                @unknown default: break
                }
            }
            Button("Decrease \(name) share", systemImage: "minus") { set(percent - 1) }
                .disabled(percent == 0)
            Button("Increase \(name) share", systemImage: "plus") { set(percent + 1) }
                .disabled(!canGrow)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
