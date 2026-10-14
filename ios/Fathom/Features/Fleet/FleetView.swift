import MapKit
import SwiftUI

/// Full-screen chart of every voyage, with a glass panel for vessels, voyages and cargo.
struct FleetView: View {
    @Environment(Ledger.self) private var ledger
    @Environment(SeaRoutes.self) private var seaRoutes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var path = NavigationPath()
    @State private var camera = MapCameraPosition.automatic
    @State private var segment = FleetSegment.vessels
    @State private var focused: Int?
    @State private var expanded = true
    @State private var plotting = false
    @State private var adding: FleetSegment?
    @State private var failedRoutes: Set<Int> = []
    @State private var panelHeight: CGFloat = 0
    @State private var now = Date.now

    var body: some View {
        let plots = ledger.voyages.compactMap { VoyagePlot.make($0, seaRoutes: seaRoutes, now: now) }
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                FleetMap(plots: plots, focused: focused, camera: $camera, bottomInset: panelHeight) { id in
                    path.append(AppRoute.voyage(id))
                }
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    header(plots)
                    Spacer(minLength: 0)
                    FleetPanel(segment: $segment, expanded: $expanded, focused: focused, plots: plots,
                               failedRoutes: failedRoutes, onFocus: focus, onOpen: { path.append(AppRoute.voyage($0)) },
                               onPlot: { plotting = true }, onAdd: { adding = $0 })
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
                }
            }
            .foregroundStyle(Theme.ink)
            .background(Theme.abyss)
            .toolbar(.hidden, for: .navigationBar)
            .appRoutes()
        }
        .task(id: ledger.voyages.map { "\($0.id):\($0.originPort ?? "")>\($0.destPort ?? "")" }) {
            for voyage in ledger.voyages {
                if await seaRoutes.chart(voyage) { failedRoutes.remove(voyage.id) } else { failedRoutes.insert(voyage.id) }
            }
        }
        .task {
            // Ships creep along their routes; once a minute is plenty.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = .now
            }
        }
        .fullScreenCover(isPresented: $plotting) {
            PlotVoyageFlow { voyage in
                segment = .voyages
                focus(voyage.id)
            }
        }
        .sheet(item: $adding) { kind in
            if kind == .cargo { CargoEditor() } else { VesselEditor() }
        }
    }

    private func header(_ plots: [VoyagePlot]) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fleet")
                    .font(.rounded(.largeTitle, weight: .bold))
                Text(summary(plots))
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
                    .contentTransition(.numericText())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                ConnectionPill()
                if focused != nil {
                    Button("Show all", systemImage: "scope") { focus(nil) }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.glass)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .background {
            LinearGradient(colors: [Theme.abyss.opacity(0.95), Theme.abyss.opacity(0.6), .clear],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private func summary(_ plots: [VoyagePlot]) -> String {
        let atSea = plots.count { $0.state == .atSea }
        let scheduled = plots.count { $0.state == .scheduled }
        return "\(atSea) at sea · \(scheduled) scheduled · \(counted(ledger.vessels.count, "vessel"))"
    }

    private func focus(_ id: Int?) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.8)) {
            focused = id
            if let id, let plot = VoyagePlot.make(ledger.voyages.first { $0.id == id } ?? Voyage(voyageId: id),
                                                  seaRoutes: seaRoutes, now: now) {
                camera = .fitting(plot.rect)
            } else {
                camera = .automatic
            }
        }
    }
}

enum FleetSegment: String, CaseIterable, Identifiable {
    case vessels, voyages, cargo
    var id: Self { self }
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .vessels: "ferry.fill"
        case .voyages: "point.topleft.down.to.point.bottomright.curvepath"
        case .cargo: "shippingbox.fill"
        }
    }

    var tint: Color {
        switch self {
        case .vessels: Theme.sky
        case .voyages: Theme.teal
        case .cargo: Theme.amber
        }
    }
}

// MARK: - Map

private struct FleetMap: View {
    let plots: [VoyagePlot]
    let focused: Int?
    @Binding var camera: MapCameraPosition
    let bottomInset: CGFloat
    let onOpen: (Int) -> Void
    @Environment(Ledger.self) private var ledger

    var body: some View {
        let ports = Dictionary(plots.flatMap { [$0.origin, $0.destination] }.map { ($0.id, $0) }) { a, _ in a }
        let focusedPlot = plots.first { $0.id == focused }
        MapReader { proxy in
            Map(position: $camera, interactionModes: [.pan, .zoom]) {
                ForEach(plots) { plot in
                    let dimmed = focused != nil && focused != plot.id
                    ForEach(plot.segments) { segment in
                        MapPolyline(coordinates: segment.path)
                            .stroke(plot.state.tint.opacity(dimmed ? 0.25 : 0.9),
                                    style: StrokeStyle(lineWidth: focused == plot.id ? 5 : 3, lineCap: .round, lineJoin: .round,
                                                       dash: plot.state == .scheduled ? [8, 6] : []))
                    }
                }
                ForEach(Array(ports.values)) { port in
                    let highlighted = focusedPlot.map { $0.origin == port || $0.destination == port } ?? false
                    Annotation(port.name, coordinate: port.coordinate) {
                        PortPin(port: port, highlighted: highlighted)
                    }
                    .annotationTitles(.hidden)
                }
                ForEach(plots) { plot in
                    Annotation(shipTitle(plot), coordinate: plot.ship) {
                        Button { onOpen(plot.id) } label: {
                            ShipMarker(heading: plot.heading, tint: plot.state.tint, underway: plot.state == .atSea)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Ship on \(plot.voyage.routeTitle), \(plot.state.label), estimated position")
                        .accessibilityHint("Opens the voyage")
                    }
                    .annotationTitles(focused == nil || focused == plot.id ? .automatic : .hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
            .safeAreaPadding(.bottom, bottomInset)
            .safeAreaPadding(.top, 90)
            .onTapGesture { point in
                if let id = voyage(near: point, proxy: proxy) { onOpen(id) }
            }
        }
    }

    private func shipTitle(_ plot: VoyagePlot) -> String {
        let vessel = ledger.vessels.first { $0.id == plot.voyage.vesselId }?.name ?? "Ship"
        return plot.state == .atSea ? "\(vessel) (est.)" : vessel
    }

    /// The voyage line closest to a tap, if it's within a finger's width.
    private func voyage(near point: CGPoint, proxy: MapProxy) -> Int? {
        var best: (id: Int, distance: CGFloat)?
        for plot in plots {
            for segment in plot.segments {
                let points = segment.path.compactMap { proxy.convert($0, to: .local) }
                for (a, b) in zip(points, points.dropFirst()) {
                    let d = Self.distance(from: point, toSegment: a, b)
                    if d < (best?.distance ?? 22) { best = (plot.id, d) }
                }
            }
        }
        return best?.id
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared)) : 0
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}
