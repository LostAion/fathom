import Charts
import MapKit
import SwiftUI

/// Dashboard: exposure, book by type, expiries, voyages and the work queue.
struct BridgeView: View {
    @Environment(Ledger.self) private var ledger
    @Environment(ConnectionMonitor.self) private var connection

    private enum Route: Hashable { case lab }

    @State private var path = NavigationPath()
    @State private var creating: QuickCreate.Kind?
    @State private var created: AppRoute?

    var body: some View {
        NavigationStack(path: $path) {
            Screen(title: "Bridge", subtitle: "Underwriting at a glance") {
                LedgerStatusCard()
                QuickCreate { creating = $0 }
                if ledger.hasLoaded && ledger.policies.isEmpty {
                    GlassCard {
                        Label("No policies yet. Tap New policy above to issue your first one. Charts and figures appear here once you have some.",
                              systemImage: "sparkles")
                            .font(.callout)
                            .foregroundStyle(Theme.inkMuted)
                    }
                } else if ledger.hasLoaded {
                    let metrics = BridgeMetrics(policies: ledger.policies, claims: ledger.claims,
                                                reinsuredBy: ledger.reinsuredBy, assessedBy: ledger.assessedBy)
                    ExposureCard(metrics: metrics)
                    KeyFigures(metrics: metrics)
                    BookByType(metrics: metrics)
                    ExpiringSoon(counts: metrics.expiring)
                    VoyageStrip()
                    AttentionList(items: metrics.attention)
                    NavigationLink(value: Route.lab) { LabLink() }
                        .buttonStyle(.plain)
                }
            }
            .refreshable {
                await connection.check()
                await ledger.refresh()
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { _ in ConcurrencyLabView() }
            .appRoutes()
        }
        .fullScreenCover(item: $creating, onDismiss: openCreated) { kind in
            switch kind {
            case .policy: IssuePolicyFlow { created = .policy($0) }
            case .claim: FileClaimFlow { created = .claim($0) }
            case .voyage: PlotVoyageFlow { created = .voyage($0.id) }
            }
        }
    }

    private func openCreated() {
        guard let created else { return }
        self.created = nil
        path.append(created)
    }
}

// MARK: - Create

/// The three things people make most, as big buttons at the top of the dashboard.
private struct QuickCreate: View {
    enum Kind: Identifiable {
        case policy, claim, voyage
        var id: Self { self }
    }

    let create: (Kind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Create")
            HStack(spacing: 10) {
                button("New policy", symbol: "shield.lefthalf.filled", tint: Theme.teal, kind: .policy)
                button("File claim", symbol: "lifepreserver", tint: Theme.coral, kind: .claim)
                button("Plot voyage", symbol: "map", tint: Theme.sky, kind: .voyage)
            }
        }
    }

    private func button(_ title: String, symbol: String, tint: Color, kind: Kind) -> some View {
        Button { create(kind) } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.title2)
                Text(title)
                    .font(.rounded(.subheadline, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.roundedRectangle(radius: 20))
        .tint(tint)
    }
}

private func typeLabel(_ type: PolicyType) -> String {
    switch type {
    case .hull: "Hull"
    case .cargo: "Cargo"
    case .pi: "P&I"
    }
}

private func percent(_ value: Double?, digits: Int = 0) -> String {
    value.map { $0.formatted(.percent.precision(.fractionLength(digits))) } ?? "–"
}

// MARK: - Exposure

private struct ExposureCard: View {
    let metrics: BridgeMetrics

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionHeader(title: "Total sum insured")
                    Text(metrics.totalInsured.compactMoney)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("across \(counted(metrics.live.count, "live policy", "live policies"))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkMuted)
                }
                .accessibilityElement(children: .combine)

                StageBar(slices: metrics.byStage, total: metrics.totalInsured)

                Divider()

                Label {
                    Text("\(percent(metrics.cededShare)) reinsured (\(metrics.ceded.compactMoney)), \((metrics.totalInsured - metrics.ceded).compactMoney) retained")
                } icon: {
                    Image(systemName: "building.columns.fill")
                        .foregroundStyle(Theme.lavender)
                }
                .font(.callout)
            }
        }
    }
}

/// Sum insured split by lifecycle stage. Status colours, each with a direct label.
private struct StageBar: View {
    let slices: [BridgeMetrics.StageSlice]
    let total: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let visible = slices.filter { $0.sumInsured > 0 }
                let gaps = CGFloat(max(visible.count - 1, 0)) * 2
                HStack(spacing: 2) {
                    ForEach(visible) { slice in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(slice.stage.tint)
                            .frame(width: max((geo.size.width - gaps) * CGFloat((slice.sumInsured / max(total, 1)).double), 4))
                    }
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 16) {
                ForEach(slices) { slice in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle().fill(slice.stage.tint).frame(width: 8, height: 8)
                            Text(slice.stage == .bound ? "Bound" : slice.stage.rawValue.capitalized)
                                .font(.caption.weight(.semibold))
                        }
                        Text(slice.sumInsured.compactMoney)
                            .font(.rounded(.subheadline, weight: .semibold))
                        Text(counted(slice.count, "policy", "policies"))
                            .font(.caption2)
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - Key figures

private struct KeyFigures: View {
    let metrics: BridgeMetrics
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        let overLimit = (metrics.lossRatio ?? 0) > 1
        layout {
            StatTile(title: "Premium", value: metrics.premium.compactMoney, caption: "written")
            StatTile(title: "Loss ratio", value: percent(metrics.lossRatio),
                     caption: overLimit ? "Over 100%" : "\(metrics.incurred.compactMoney) incurred",
                     warning: overLimit)
            StatTile(title: "Rate on line", value: percent(metrics.rateOnLine, digits: 2), caption: "of sum insured")
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let caption: String
    var warning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
            Text(value)
                .font(.rounded(.title2, weight: .bold))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if warning { Image(systemName: "exclamationmark.triangle.fill") }
                Text(caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption2)
            .foregroundStyle(warning ? Theme.coral : Theme.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Book by type

private struct BookByType: View {
    let metrics: BridgeMetrics

    private enum Mode: String, CaseIterable { case premium = "Premium", lossRatio = "Loss ratio", table = "Table" }
    @State private var mode = Mode.premium

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Book by type")
                Picker("Show", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .premium: premiumChart
                case .lossRatio: lossRatioChart
                case .table: table
                }
            }
        }
        .sensoryFeedback(.selection, trigger: mode)
    }

    private var premiumChart: some View {
        Chart(metrics.byType) { slice in
            BarMark(x: .value("Premium", slice.premium.double), y: .value("Type", typeLabel(slice.type)), height: .fixed(18))
                .foregroundStyle(slice.type.tint)
                .clipShape(.rect(cornerRadius: 4))
                .annotation(position: .trailing, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    barLabel(slice.type, "\(slice.premium.compactMoney) · \(counted(slice.count, "policy", "policies"))")
                }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...max(metrics.byType.map(\.premium.double).max() ?? 1, 1) * 1.9)
        .frame(height: 130)
    }

    private var lossRatioChart: some View {
        let ratios = metrics.byType.compactMap { slice in slice.lossRatio.map { (slice, $0) } }
        let top = max(ratios.map(\.1).max() ?? 1, 1)
        return Chart {
            ForEach(ratios, id: \.0.id) { slice, ratio in
                BarMark(x: .value("Loss ratio", ratio), y: .value("Type", typeLabel(slice.type)), height: .fixed(18))
                    .foregroundStyle(slice.type.tint)
                    .clipShape(.rect(cornerRadius: 4))
                    .annotation(position: .trailing, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        barLabel(slice.type, percent(ratio))
                    }
            }
            RuleMark(x: .value("Break-even", 1.0))
                .foregroundStyle(Theme.inkMuted.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .annotation(position: .bottom, alignment: .leading, spacing: 4) {
                    Text("100% break-even").font(.caption2).foregroundStyle(Theme.inkMuted)
                }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...top * 1.5)
        .frame(height: 150)
        .overlay {
            if ratios.isEmpty {
                Text("No premium written yet").font(.callout).foregroundStyle(Theme.inkMuted)
            }
        }
    }

    private func barLabel(_ type: PolicyType, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(typeLabel(type)).fontWeight(.semibold).foregroundStyle(Theme.ink)
            Text(value).foregroundStyle(Theme.inkMuted)
        }
        .font(.caption)
    }

    private var table: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Type"); Text("Policies"); Text("Premium"); Text("Incurred"); Text("Loss ratio")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.inkMuted)
            ForEach(metrics.byType) { slice in
                Divider()
                GridRow {
                    Text(typeLabel(slice.type)).fontWeight(.semibold)
                    Text("\(slice.count)")
                    Text(slice.premium.compactMoney)
                    Text(slice.incurred.compactMoney)
                    Text(percent(slice.lossRatio))
                }
                .font(.caption)
            }
        }
    }
}

// MARK: - Expiring

private struct ExpiringSoon: View {
    let counts: [Int]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Expiring soon")
                HStack(spacing: 0) {
                    ForEach(Array(zip(["0–30 days", "31–60 days", "61–90 days"], counts)), id: \.0) { label, count in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text("\(count)")
                                    .font(.rounded(.title, weight: .bold))
                                if label.hasPrefix("0") && count > 0 {
                                    Image(systemName: "hourglass")
                                        .foregroundStyle(Theme.amber)
                                }
                            }
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(Theme.inkMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

// MARK: - Voyages

/// Small map of every voyage along its sea route. Tapping opens the Fleet tab.
private struct VoyageStrip: View {
    @Environment(Ledger.self) private var ledger
    @Environment(SeaRoutes.self) private var seaRoutes
    @Environment(\.openTab) private var openTab
    @State private var camera = MapCameraPosition.automatic

    private var legs: [(voyage: Voyage, from: Port, to: Port)] {
        ledger.voyages.compactMap { voyage in
            guard let from = PortCatalog.named(voyage.originPort), let to = PortCatalog.named(voyage.destPort) else { return nil }
            return (voyage, from, to)
        }
    }

    var body: some View {
        // Read the cache here, not inside the map builder, so new routes redraw the map.
        let routes = legs.map { seaRoutes.cached(from: $0.from, to: $0.to) }
        Map(position: $camera, interactionModes: []) {
            ForEach(Array(zip(legs, routes)), id: \.0.voyage.id) { leg, route in
                if let route {
                    MapPolyline(coordinates: route.path)
                        .stroke(Theme.teal, lineWidth: 3)
                } else {
                    MapPolyline(coordinates: [leg.from.coordinate, leg.to.coordinate], contourStyle: .geodesic)
                        .stroke(Theme.teal.opacity(0.5), lineWidth: 2)
                }
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .allowsHitTesting(false)
        .frame(height: 180)
        .clipShape(.rect(cornerRadius: 24))
        // The map view swallows taps even with hit testing off, so the button sits on top.
        .overlay {
            Button { openTab(.fleet) } label: {
                Color.clear
                    .contentShape(.rect)
                    .overlay(alignment: .topLeading) {
                        Label("\(counted(ledger.voyages.count, "voyage")) · Open Fleet", systemImage: "ferry.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassEffect(.regular, in: .capsule)
                            .padding(12)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Map of \(counted(ledger.voyages.count, "voyage")). Opens Fleet.")
        }
        .task(id: legs.map(\.voyage.id)) {
            for leg in legs {
                _ = try? await seaRoutes.route(from: leg.from, to: leg.to)
            }
            // Refit once the real routes replace the straight placeholders.
            camera = .automatic
        }
    }
}

// MARK: - Attention

private struct AttentionList: View {
    let items: [BridgeMetrics.Attention]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Needs attention", count: items.count)
            if items.isEmpty {
                GlassCard(tint: Theme.teal) {
                    Label("All clear. Nothing waiting on you.", systemImage: "checkmark.seal.fill")
                }
            }
            ForEach(items) { item in
                NavigationLink(value: item.route) {
                    HStack(spacing: 14) {
                        Image(systemName: symbol(item.kind))
                            .font(.title3)
                            .foregroundStyle(tint(item.kind))
                            .frame(width: 40, height: 40)
                            .background(tint(item.kind).opacity(0.15), in: .rect(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.rounded(.headline))
                            Text(item.detail).font(.caption).foregroundStyle(Theme.inkMuted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .padding(12)
                    .contentShape(.rect)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func symbol(_ kind: BridgeMetrics.Attention.Kind) -> String {
        switch kind {
        case .quote: "doc.badge.clock"
        case .bind: "signature"
        case .survey: "magnifyingglass"
        case .expiring: "hourglass"
        case .unplaced: "building.columns"
        }
    }

    private func tint(_ kind: BridgeMetrics.Attention.Kind) -> Color {
        switch kind {
        case .quote, .bind, .expiring: Theme.amber
        case .survey: Theme.coral
        case .unplaced: Theme.lavender
        }
    }
}

private struct LabLink: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.rotation")
                .font(.title2)
                .foregroundStyle(Theme.teal)
                .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 4)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Concurrency Lab")
                    .font(.rounded(.headline))
                Text("Watch two adjusters race for the same policy limit, with and without row locking.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
        }
        .padding(16)
        .contentShape(.rect)
        .glassEffect(.regular.tint(Theme.teal.opacity(0.15)).interactive(), in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}
