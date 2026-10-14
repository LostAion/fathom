import MapKit
import SwiftUI

/// One voyage: its route on a small chart, the estimated passage, the vessel and the cargo it carries.
struct VoyageDetailView: View {
    let voyageId: Int

    @Environment(Ledger.self) private var ledger
    @Environment(SeaRoutes.self) private var seaRoutes
    @State private var editing = false
    @State private var routeFailed = false
    @State private var cargoError: String?
    @State private var changes = 0

    private var voyage: Voyage? { ledger.voyages.first { $0.id == voyageId } }

    var body: some View {
        DetailPage {
            if let voyage {
                let plot = VoyagePlot.make(voyage, seaRoutes: seaRoutes, now: .now)
                if let plot {
                    routeChart(plot)
                }
                header(voyage, plot: plot)
                if let plot, let passage = plot.passage {
                    progress(plot, passage: passage)
                }
                vessel(voyage)
                cargo(voyage)
            } else {
                ContentUnavailableView("Voyage removed", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
        }
        .navigationTitle("Voyage #\(voyageId)")
        .modifier(VoyageActions(voyage: voyage, editing: $editing))
        .task(id: voyage.map { "\($0.originPort ?? "")>\($0.destPort ?? "")" }) {
            guard let voyage else { return }
            routeFailed = !(await seaRoutes.chart(voyage))
        }
        .sheet(isPresented: $editing) {
            if let voyage { VoyageEditor(voyage: voyage) }
        }
        .sensoryFeedback(.success, trigger: changes)
    }

    // MARK: - Sections

    private func routeChart(_ plot: VoyagePlot) -> some View {
        Map(position: .constant(.fitting(plot.rect, padding: 0.2)), interactionModes: []) {
            ForEach(plot.segments) { segment in
                MapPolyline(coordinates: segment.path)
                    .stroke(plot.state.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round,
                                                               dash: plot.state == .scheduled ? [8, 6] : []))
            }
            Annotation(plot.origin.name, coordinate: plot.origin.coordinate) { PortPin(port: plot.origin) }
                .annotationTitles(.hidden)
            Annotation(plot.destination.name, coordinate: plot.destination.coordinate) { PortPin(port: plot.destination) }
                .annotationTitles(.hidden)
            Annotation("Estimated position", coordinate: plot.ship) {
                ShipMarker(heading: plot.heading, tint: plot.state.tint, underway: plot.state == .atSea)
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .frame(height: 220)
        .clipShape(.rect(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.inkMuted.opacity(0.25)))
        .accessibilityElement()
        .accessibilityLabel("Chart of the route from \(plot.origin.name) to \(plot.destination.name)")
    }

    private func header(_ voyage: Voyage, plot: VoyagePlot?) -> some View {
        let state = plot?.state ?? VoyageState.classify(depart: voyage.departs, hoursAtSea: nil, now: .now)
        let locator = PortLocator.shared
        return GlassCard(tint: state.tint) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Voyage", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(state.tint)
                    Spacer()
                    StatusChip(text: state.label, tint: state.tint)
                }
                HStack(alignment: .top, spacing: 8) {
                    portColumn(voyage.originPort, port: locator.port(named: voyage.originPort), role: "From", alignment: .leading)
                    Image(systemName: "arrow.right")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.inkMuted)
                        .padding(.top, 12)
                        .accessibilityHidden(true)
                    portColumn(voyage.destPort, port: locator.port(named: voyage.destPort), role: "To", alignment: .trailing)
                }
                Divider()
                HStack(alignment: .top, spacing: 0) {
                    stat(plot.map { $0.track.isSeaLane || routeFailed ? $0.track.distanceText : "…" } ?? "–",
                         plot.map { $0.track.isSeaLane ? "via sea lanes" : "approx. great circle" } ?? "distance")
                    stat(voyage.departs?.dayText ?? "–", "departs")
                    stat(plot?.passage?.arrival.dayText ?? "–", "arrives (est.)")
                }
            }
        }
    }

    private func portColumn(_ name: String?, port: Port?, role: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(port?.flagOrPin ?? "📍")
                .font(.largeTitle)
            Text(name ?? "Unknown")
                .font(.rounded(.title3, weight: .bold))
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
            Text(role)
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
        .accessibilityElement(children: .combine)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.rounded(.headline, weight: .bold))
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func progress(_ plot: VoyagePlot, passage: Passage) -> some View {
        let day = Calendar.current.dateComponents([.day], from: passage.depart, to: .now).day ?? 0
        let caption = switch plot.state {
        case .scheduled: "Sails in \(counted(max(-day, 1), "day"))"
        case .atSea: "Day \(day + 1) of about \(Int(passage.days.rounded(.up)))"
        case .arrived: "Arrived about \(passage.arrival.dayText)"
        }
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(caption)
                        .font(.rounded(.headline))
                    Spacer()
                    Text(plot.progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.rounded(.headline, weight: .bold))
                        .foregroundStyle(plot.state.tint)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.inkMuted.opacity(0.2))
                        Capsule().fill(plot.state.tint.gradient)
                            .frame(width: max(8, geo.size.width * plot.progress))
                        HullShape()
                            .fill(Theme.ink)
                            .frame(width: 8, height: 16)
                            .rotationEffect(.degrees(90))
                            .offset(x: max(0, geo.size.width * plot.progress - 8))
                    }
                }
                .frame(height: 10)
                .accessibilityHidden(true)
                Text("Estimated at \(Passage.assumedKnots.formatted()) knots from the departure date. Distance and ETA are computed, not stored.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(plot.progress.formatted(.percent.precision(.fractionLength(0))))
    }

    @ViewBuilder
    private func vessel(_ voyage: Voyage) -> some View {
        SectionHeader(title: "Vessel")
        if let vessel = ledger.vessels.first(where: { $0.id == voyage.vesselId }) {
            NavigationLink(value: AppRoute.vessel(vessel.id)) {
                VesselRow(vessel: vessel, detail: vessel.tonnage.map { "\($0.formatted()) GT" })
            }
            .buttonStyle(.plain)
        } else {
            NoneYet(text: "No vessel assigned")
        }
    }

    @ViewBuilder
    private func cargo(_ voyage: Voyage) -> some View {
        let carriedIDs = Set(ledger.carries.filter { $0.voyageId == voyage.id }.map(\.cargoId))
        let carried = ledger.cargos.filter { carriedIDs.contains($0.id) }
        let available = ledger.cargos.filter { !carriedIDs.contains($0.id) }
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "Cargo carried", count: carried.count)
                if !carried.isEmpty {
                    Text("\(carried.compactMap(\.valueAmount).reduce(0, +).money) aboard")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            Spacer()
            Menu {
                ForEach(available) { cargo in
                    Button(cargo.description ?? "Cargo #\(cargo.id)") {
                        Task { await change { try await ledger.save(Carries(voyageId: voyage.id, cargoId: cargo.id), isNew: true) } }
                    }
                }
            } label: {
                Label("Load cargo", systemImage: "plus")
                    .font(.rounded(.subheadline, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.amber)
            .disabled(available.isEmpty)
        }
        if let cargoError {
            Label(cargoError, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(Theme.coral)
        }
        if carried.isEmpty {
            NoneYet(text: "Nothing in the hold")
        }
        ForEach(carried) { cargo in
            HStack(spacing: 8) {
                NavigationLink(value: AppRoute.cargo(cargo.id)) { CargoRow(cargo: cargo) }
                    .buttonStyle(.plain)
                Button("Unload \(cargo.description ?? "cargo")", systemImage: "minus.circle.fill") {
                    Task { await change { try await ledger.delete(Carries(voyageId: voyage.id, cargoId: cargo.id)) } }
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(Theme.coral)
            }
            .transition(.opacity.combined(with: .move(edge: .leading)))
        }
    }

    private func change(_ action: () async throws -> Void) async {
        cargoError = nil
        do {
            try await action()
            changes += 1
        } catch {
            cargoError = error.localizedDescription
        }
    }
}

private struct VoyageActions: ViewModifier {
    let voyage: Voyage?
    @Binding var editing: Bool
    @Environment(Ledger.self) private var ledger

    func body(content: Content) -> some View {
        let links = ledger.carries.count { $0.voyageId == voyage?.id }
        content.recordActions(
            available: voyage != nil, name: "voyage \(voyage?.routeTitle ?? "")", deleteLabel: "Delete voyage",
            effect: links == 0
                ? "No cargo is linked to this voyage."
                : "\(counted(links, "cargo link")) will be deleted too (ON DELETE CASCADE). The cargo stays on file.",
            editing: $editing
        ) { if let voyage { try await ledger.delete(voyage) } }
    }
}
