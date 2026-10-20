import SwiftUI

/// Glass panel over the Fleet map: vessel passports, the voyage list and the cargo hold.
struct FleetPanel: View {
    @Binding var segment: FleetSegment
    @Binding var expanded: Bool
    let focused: Int?
    let plots: [VoyagePlot]
    let failedRoutes: Set<Int>
    let onFocus: (Int?) -> Void
    let onOpen: (Int) -> Void
    let onPlot: () -> Void
    let onAdd: (FleetSegment) -> Void

    @Environment(Ledger.self) private var ledger

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                SegmentSwitch(selection: $segment) { count(of: $0) }
                Button(expanded ? "Collapse panel" : "Expand panel", systemImage: "chevron.down") {
                    withAnimation(.snappy) { expanded.toggle() }
                }
                .labelStyle(.iconOnly)
                .font(.subheadline.weight(.bold))
                .rotationEffect(.degrees(expanded ? 0 : 180))
                .frame(width: 40, height: 40)
                .foregroundStyle(Theme.inkMuted)
                .contentShape(.circle)
            }
            if expanded {
                Group {
                    if !ledger.hasLoaded || ledger.loadError != nil {
                        LedgerStatusCard()
                    } else {
                        switch segment {
                        case .vessels: vessels
                        case .voyages: voyages
                        case .cargo: cargo
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .sensoryFeedback(.selection, trigger: segment)
        .onChange(of: segment) { if !expanded { withAnimation(.snappy) { expanded = true } } }
    }

    // MARK: - Vessels

    private var vessels: some View {
        let vessels = ledger.vessels.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        return VStack(alignment: .leading, spacing: 10) {
            title("Vessels", count: vessels.count) {
                Button("Add vessel", systemImage: "plus") { onAdd(.vessels) }
                    .tint(Theme.sky)
            }
            if vessels.isEmpty {
                empty("No vessels yet. Add the first ship to the fleet.", symbol: "ferry")
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(vessels) { vessel in
                            NavigationLink(value: AppRoute.vessel(vessel.id)) {
                                PassportCard(vessel: vessel,
                                             policies: ledger.policies.count { $0.vesselId == vessel.id && $0.isInForce },
                                             voyages: ledger.voyages.count { $0.vesselId == vessel.id })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .accessibilityIdentifier("Vessel carousel")
            }
        }
    }

    // MARK: - Voyages

    private var voyages: some View {
        let byID = Dictionary(plots.map { ($0.id, $0) }) { a, _ in a }
        let order: [VoyageState: Int] = [.atSea: 0, .scheduled: 1, .arrived: 2]
        let voyages = ledger.voyages.sorted {
            let a = order[byID[$0.id]?.state ?? .scheduled]!, b = order[byID[$1.id]?.state ?? .scheduled]!
            return a != b ? a < b : ($0.departDate ?? "") < ($1.departDate ?? "")
        }
        return VStack(alignment: .leading, spacing: 10) {
            title("Voyages", count: voyages.count) {
                Button("Plot voyage", systemImage: "point.topleft.down.to.point.bottomright.curvepath") { onPlot() }
                    .tint(Theme.teal)
            }
            if voyages.isEmpty {
                empty("No voyages yet. Plot one on the chart.", symbol: "map")
            } else {
                ScrollViewReader { proxy in
                    CappedScroll(maxHeight: 300) {
                        VStack(spacing: 8) {
                            ForEach(voyages) { voyage in
                                voyageRow(voyage, plot: byID[voyage.id])
                                    .id(voyage.id)
                            }
                        }
                    }
                    .onChange(of: focused) {
                        guard let focused else { return }
                        withAnimation(.snappy) { proxy.scrollTo(focused, anchor: .center) }
                    }
                }
            }
        }
    }

    private func voyageRow(_ voyage: Voyage, plot: VoyagePlot?) -> some View {
        let isFocused = focused == voyage.id
        let state = plot?.state ?? VoyageState.classify(depart: voyage.departs, hoursAtSea: nil, now: .now)
        return VStack(spacing: 8) {
            Button { onFocus(isFocused ? nil : voyage.id) } label: {
                VoyageRow(voyage: voyage, distance: distance(voyage, plot: plot), state: state, selected: isFocused)
            }
            .buttonStyle(.plain)
            .accessibilityHint(isFocused ? "Shows all voyages" : "Shows this route on the chart")
            if isFocused {
                Button("Open voyage", systemImage: "arrow.up.forward") { onOpen(voyage.id) }
                    .font(.rounded(.subheadline, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .buttonStyle(.glassProminent)
                    .tint(state.tint)
                    .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
            }
        }
    }

    private func distance(_ voyage: Voyage, plot: VoyagePlot?) -> String? {
        guard let plot else {
            return failedRoutes.contains(voyage.id) ? "Port not on chart" : nil
        }
        if plot.track.isSeaLane { return plot.track.distanceText }
        return failedRoutes.contains(voyage.id) ? "≈ \(plot.track.distanceText) (approx.)" : nil
    }

    // MARK: - Cargo

    private var cargo: some View {
        let cargos = ledger.cargos.sorted { ($0.valueAmount ?? 0) > ($1.valueAmount ?? 0) }
        let total = cargos.compactMap(\.valueAmount).reduce(0, +)
        return VStack(alignment: .leading, spacing: 10) {
            title("Cargo hold", count: cargos.count, detail: cargos.isEmpty ? nil : "\(total.compactMoney) declared") {
                Button("Add cargo", systemImage: "plus") { onAdd(.cargo) }
                    .tint(Theme.amber)
            }
            if cargos.isEmpty {
                empty("The hold is empty. Add a consignment.", symbol: "shippingbox")
            } else {
                CappedScroll(maxHeight: 300) {
                    VStack(spacing: 8) {
                        ForEach(cargos) { cargo in
                            NavigationLink(value: AppRoute.cargo(cargo.id)) {
                                let trips = ledger.carries.count { $0.cargoId == cargo.id }
                                CargoRow(cargo: cargo, detail: trips == 0 ? "Not on a voyage" : "On \(counted(trips, "voyage"))")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Pieces

    private func title<Action: View>(_ text: String, count: Int, detail: String? = nil,
                                     @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: text, count: count)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            Spacer()
            action()
                .font(.rounded(.subheadline, weight: .semibold))
                .foregroundStyle(.white)
                .buttonStyle(.glassProminent)
        }
    }

    private func empty(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(Theme.inkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func count(of segment: FleetSegment) -> Int {
        switch segment {
        case .vessels: ledger.vessels.count
        case .voyages: ledger.voyages.count
        case .cargo: ledger.cargos.count
        }
    }
}

/// Scrolls only when the content is taller than `maxHeight`; otherwise hugs it.
struct CappedScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollView {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .frame(height: min(max(height, 1), maxHeight))
        .scrollBounceBehavior(.basedOnSize)
        .scrollClipDisabled()
    }
}

private struct SegmentSwitch: View {
    @Binding var selection: FleetSegment
    let count: (FleetSegment) -> Int
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(FleetSegment.allCases) { segment in
                let selected = segment == selection
                Button {
                    withAnimation(.snappy) { selection = segment }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: segment.symbol)
                            .font(.caption.weight(.bold))
                        Text(segment.title)
                    }
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(selected ? segment.tint : Theme.inkMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if selected {
                            Capsule()
                                .fill(segment.tint.opacity(0.18))
                                .matchedGeometryEffect(id: "segment", in: namespace)
                        }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(segment.title)
                .accessibilityValue("\(count(segment))")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.inkMuted.opacity(0.12), in: .capsule)
    }
}
