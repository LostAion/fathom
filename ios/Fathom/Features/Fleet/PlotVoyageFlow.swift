import MapKit
import SwiftUI

/// Map-first voyage planner: pick two ports on the chart, watch the sea lane draw in,
/// then set speed, date, vessel and cargo. Same step bar and haptics as `GuidedFlow`,
/// but the map stays on screen the whole way.
struct PlotVoyageFlow: View {
    var onPlotted: (Voyage) -> Void

    @Environment(Ledger.self) private var ledger
    @Environment(SeaRoutes.self) private var seaRoutes
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step = Step.origin
    @State private var forward = true
    @State private var origin: Port?
    @State private var destination: Port?
    @State private var search = ""
    @State private var track: VoyageTrack?
    @State private var routeFailed = false
    @State private var drawn = 0.0
    @State private var preview = 0.0
    @State private var knots = Passage.assumedKnots
    @State private var depart = Calendar.gmt.startOfDay(for: .now.addingTimeInterval(86_400))
    @State private var vesselId: Int?
    @State private var cargoIds: Set<Int> = []
    @State private var created: Voyage?
    @State private var camera = MapCameraPosition.automatic
    @State private var busy = false
    @State private var error: String?
    @State private var cardHeight: CGFloat = 0
    @State private var screenHeight: CGFloat = 800
    @State private var advances = 0
    @State private var finishes = 0
    @State private var picks = 0
    @State private var addingVessel = false
    @State private var addingCargo = false

    enum Step: Int, CaseIterable {
        case origin, destination, speed, departure, vessel, cargo, review

        var title: String {
            switch self {
            case .origin: "Origin"
            case .destination: "Destination"
            case .speed: "Speed"
            case .departure: "Departure"
            case .vessel: "Vessel"
            case .cargo: "Cargo"
            case .review: "Review"
            }
        }

        var prompt: String {
            switch self {
            case .origin: "Where does she sail from?"
            case .destination: "Where is she bound?"
            case .speed: "How fast will she steam?"
            case .departure: "When does she sail?"
            case .vessel: "Which ship makes the passage?"
            case .cargo: "Anything in the hold?"
            case .review: "Ready to plot"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            chart
                .ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                card
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { screenHeight = $0 }
        .foregroundStyle(Theme.ink)
        .background(Theme.abyss)
        .task(id: "\(origin?.id ?? "")>\(destination?.id ?? "")") { await chartRoute() }
        .task(id: step) { await sailPreview() }
        .sensoryFeedback(.impact(weight: .light), trigger: advances)
        .sensoryFeedback(.selection, trigger: picks)
        .sensoryFeedback(.success, trigger: finishes)
        .sheet(isPresented: $addingVessel) {
            VesselEditor { vessel in
                withAnimation(.snappy) { vesselId = vessel.id }
            }
        }
        .sheet(isPresented: $addingCargo) {
            CargoEditor { cargo in
                withAnimation(.snappy) { _ = cargoIds.insert(cargo.id) }
            }
        }
    }

    // MARK: - Map

    private var chart: some View {
        let path = track.map { RouteGeometry.prefix(of: $0.path, fraction: drawn) } ?? []
        let ports = step.rawValue <= Step.destination.rawValue ? PortCatalog.all : [origin, destination].compactMap { $0 }
        return Map(position: $camera, interactionModes: [.pan, .zoom]) {
            ForEach(RouteGeometry.mapSegments(path).enumerated().map { RouteSegment(id: "\($0.offset)", path: $0.element) }) { segment in
                MapPolyline(coordinates: segment.path)
                    .stroke(Theme.teal, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round,
                                                           dash: routeFailed ? [8, 6] : []))
            }
            ForEach(ports) { port in
                Annotation(port.name, coordinate: port.coordinate) {
                    Button { pick(port) } label: {
                        PortPin(port: port, highlighted: port == origin || port == destination,
                                tint: port == origin ? Theme.teal : Theme.amber)
                    }
                    .buttonStyle(.plain)
                    .disabled(step.rawValue > Step.destination.rawValue)
                    .accessibilityLabel("\(port.name) pin")
                    .accessibilityIdentifier("pin-\(port.name)")
                }
                .annotationTitles(.hidden)
            }
            if let track, step.rawValue >= Step.speed.rawValue,
               let ship = RouteGeometry.point(along: track.path, fraction: preview) {
                Annotation("Preview", coordinate: RouteGeometry.normalized(ship)) {
                    ShipMarker(heading: RouteGeometry.heading(along: track.path, fraction: preview), tint: Theme.teal)
                        .accessibilityHidden(true)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .safeAreaPadding(.top, 110)
        .safeAreaPadding(.bottom, cardHeight)
    }

    // MARK: - Chrome

    private var topBar: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
                Spacer()
                VStack(spacing: 2) {
                    Text("Plot voyage")
                        .font(.rounded(.headline))
                    Text("Step \(step.rawValue + 1) of \(Step.allCases.count)")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .contentTransition(.numericText())
                }
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? Theme.teal : Theme.inkMuted.opacity(0.25))
                        .frame(height: 4)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count): \(step.title)")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .background {
            LinearGradient(colors: [Theme.abyss.opacity(0.95), Theme.abyss.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(step.prompt)
                .font(.rounded(.title2, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            CappedScroll(maxHeight: max(screenHeight * 0.42, 260)) {
                stepContent
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(step)
            .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                    removal: .opacity))
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Theme.coral)
            }
            HStack(spacing: 12) {
                if step != .origin {
                    Button("Back") { move(by: -1) }
                        .buttonStyle(.glass)
                        .disabled(busy)
                }
                Button {
                    if step == .review { Task { await finish() } } else { move(by: 1) }
                } label: {
                    HStack {
                        if busy { ProgressView() }
                        Text(step == .review ? "Plot voyage" : "Next")
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.white)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.teal)
                .disabled(!isComplete || busy)
                .accessibilityIdentifier(step == .review ? "Finish plot" : "Next step")
            }
            .font(.rounded(.headline))
            .controlSize(.large)
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .origin, .destination: portPicker
        case .speed: speed
        case .departure: departure
        case .vessel: vessels
        case .cargo: cargo
        case .review: review
        }
    }

    // MARK: - Steps

    private var portPicker: some View {
        let excluded = step == .destination ? origin : nil
        let query = search.trimmingCharacters(in: .whitespaces)
        let ports = PortCatalog.all.filter { port in
            port != excluded && (query.isEmpty
                || port.name.localizedCaseInsensitiveContains(query)
                || port.locode.localizedCaseInsensitiveContains(query)
                || (Locale.current.localizedString(forRegionCode: port.country) ?? "").localizedCaseInsensitiveContains(query))
        }
        let selected = step == .origin ? origin : destination
        return VStack(alignment: .leading, spacing: 10) {
            if step == .destination {
                routeSummary
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.inkMuted)
                TextField("Search ports or tap a pin", text: $search)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("Port search")
                if !search.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") { search = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            if ports.isEmpty {
                Text("No port in the catalog matches “\(query)”.")
                    .font(.callout)
                    .foregroundStyle(Theme.inkMuted)
            }
            LazyVStack(spacing: 6) {
                ForEach(ports) { port in
                    Button { pick(port) } label: {
                        HStack(spacing: 12) {
                            Text(port.flag).font(.title3)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(port.name).font(.rounded(.body, weight: .semibold))
                                Text(Locale.current.localizedString(forRegionCode: port.country) ?? port.country)
                                    .font(.caption)
                                    .foregroundStyle(Theme.inkMuted)
                            }
                            Spacer()
                            Text(port.locode)
                                .font(.caption.monospaced())
                                .foregroundStyle(Theme.inkMuted)
                            if port == selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.teal)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(port == selected ? Theme.teal.opacity(0.15) : .clear, in: .rect(cornerRadius: 14))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("port-\(port.name)")
                    .accessibilityAddTraits(port == selected ? .isSelected : [])
                }
            }
        }
    }

    /// Origin → destination with the distance counting up as the line draws in.
    private var routeSummary: some View {
        HStack(spacing: 10) {
            Text("\(origin?.flag ?? "") \(origin?.name ?? "")")
            Image(systemName: "arrow.right")
                .foregroundStyle(Theme.inkMuted)
            Text(destination.map { "\($0.flag) \($0.name)" } ?? "?")
                .foregroundStyle(destination == nil ? Theme.inkMuted : Theme.ink)
            Spacer()
            if destination != nil {
                if let track {
                    Text("\(Int((track.distanceNm * drawn).rounded()).formatted()) nm")
                        .font(.rounded(.headline, weight: .bold))
                        .foregroundStyle(Theme.teal)
                        .contentTransition(.numericText())
                        .accessibilityLabel("Distance \(track.distanceText)")
                } else {
                    ProgressView()
                        .accessibilityLabel("Charting the sea lane")
                }
            }
        }
        .font(.rounded(.subheadline, weight: .semibold))
        .padding(12)
        .glassEffect(.regular.tint(Theme.teal.opacity(0.12)), in: .rect(cornerRadius: 16))
    }

    private var passage: Passage? {
        track.map { Passage(depart: depart, distanceNm: $0.distanceNm, knots: knots) }
    }

    private var speed: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(knots.formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(value: knots))
                    Text("knots")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                if let passage {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(passage.days.formatted(.number.precision(.fractionLength(1))))
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.teal)
                            .contentTransition(.numericText(value: passage.days))
                        Text("days at sea")
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            Slider(value: $knots.animation(.snappy), in: 6...24, step: 0.5) {
                Text("Speed")
            } minimumValueLabel: {
                Image(systemName: "tortoise.fill")
            } maximumValueLabel: {
                Image(systemName: "hare.fill")
            }
            .tint(Theme.teal)
            .foregroundStyle(Theme.inkMuted)
            .accessibilityValue("\(knots.formatted()) knots")
            .sensoryFeedback(.selection, trigger: knots)
            if let passage {
                arrivalLine(passage)
            }
            computedNote
        }
    }

    private var departure: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("Departure date", selection: $depart, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.timeZone, .gmt)
                .tint(Theme.teal)
            if let passage {
                arrivalLine(passage)
            }
        }
    }

    private func arrivalLine(_ passage: Passage) -> some View {
        Label {
            Text("Departs \(passage.depart.dayText), arrives about \(passage.arrival.dayText)")
                .contentTransition(.numericText())
        } icon: {
            Image(systemName: "flag.checkered")
                .foregroundStyle(Theme.teal)
        }
        .font(.callout.weight(.medium))
    }

    private var computedNote: some View {
        Label("Distance and ETA are worked out on the fly from the sea lane. Only the ports, date and vessel are stored.",
              systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(Theme.inkMuted)
    }

    private var vessels: some View {
        let vessels = ledger.vessels.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        return VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(vessels) { vessel in
                        Button {
                            withAnimation(.snappy) { vesselId = vessel.id }
                            picks += 1
                        } label: {
                            PassportCard(vessel: vessel,
                                         policies: ledger.policies.count { $0.vesselId == vessel.id && $0.isInForce },
                                         voyages: ledger.voyages.count { $0.vesselId == vessel.id },
                                         selected: vesselId == vessel.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .accessibilityIdentifier("Vessel picker")
            AddNewButton(title: "Add a new vessel", tint: Theme.sky) { addingVessel = true }
        }
    }

    private var cargo: some View {
        let selected = ledger.cargos.filter { cargoIds.contains($0.id) }
        return VStack(alignment: .leading, spacing: 12) {
            ChipFlow {
                ForEach(ledger.cargos) { cargo in
                    let on = cargoIds.contains(cargo.id)
                    Button {
                        withAnimation(.snappy) {
                            if on { cargoIds.remove(cargo.id) } else { cargoIds.insert(cargo.id) }
                        }
                        picks += 1
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: on ? "checkmark.circle.fill" : "shippingbox")
                                .contentTransition(.symbolEffect(.replace))
                            Text(cargo.description ?? "Cargo #\(cargo.id)")
                                .lineLimit(2)
                            if let value = cargo.valueAmount {
                                Text(value.compactMoney)
                                    .foregroundStyle(on ? Theme.ink : Theme.inkMuted)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .foregroundStyle(on ? Theme.amber : Theme.ink)
                        .glassEffect(on ? .regular.tint(Theme.amber.opacity(0.3)).interactive() : .regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(cargo.description ?? "Cargo \(cargo.id)")
                    .accessibilityValue(cargo.valueAmount?.money ?? "")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            AddNewButton(title: "Add new cargo", tint: Theme.amber) { addingCargo = true }
            Text(selected.isEmpty
                 ? "Optional. Each consignment becomes a carries row."
                 : "\(counted(selected.count, "consignment")) · \(selected.compactMap(\.valueAmount).reduce(0, +).money) aboard")
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
                .contentTransition(.numericText())
        }
    }

    private var review: some View {
        let vessel = ledger.vessels.first { $0.id == vesselId }
        let cargos = ledger.cargos.filter { cargoIds.contains($0.id) }
        return VStack(alignment: .leading, spacing: 12) {
            routeSummary
            if let passage {
                HStack(spacing: 0) {
                    reviewStat(passage.depart.dayText, "departs")
                    reviewStat(passage.arrival.dayText, "arrives (est.)")
                    reviewStat("\(passage.days.formatted(.number.precision(.fractionLength(1)))) d", "at \(knots.formatted()) kn")
                }
            }
            if let vessel {
                VesselRow(vessel: vessel)
            }
            if cargos.isEmpty {
                Label("No cargo", systemImage: "shippingbox")
                    .font(.callout)
                    .foregroundStyle(Theme.inkMuted)
            }
            ForEach(cargos) { CargoRow(cargo: $0) }
            computedNote
        }
    }

    private func reviewStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.rounded(.subheadline, weight: .bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Logic

    private var isComplete: Bool {
        switch step {
        case .origin: origin != nil
        case .destination: destination != nil && track != nil
        case .vessel: vesselId != nil
        default: true
        }
    }

    private func move(by offset: Int) {
        guard let next = Step(rawValue: step.rawValue + offset) else { return }
        error = nil
        forward = offset > 0
        search = ""
        withAnimation(reduceMotion ? nil : .snappy) { step = next }
        if offset > 0 { advances += 1 }
        if next.rawValue >= Step.speed.rawValue, let track {
            fit(track)
        }
    }

    private func pick(_ port: Port) {
        switch step {
        case .origin:
            origin = port
            if destination == port { destination = nil }
        case .destination:
            guard port != origin else { return }
            destination = port
        default:
            return
        }
        picks += 1
        if step == .origin {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.8)) {
                camera = .region(MKCoordinateRegion(center: port.coordinate, span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 40)))
            }
        }
    }

    private func chartRoute() async {
        track = nil
        routeFailed = false
        drawn = 0
        guard let origin, let destination else { return }
        do {
            _ = try await seaRoutes.route(from: origin, to: destination)
        } catch {
            routeFailed = true
        }
        guard !Task.isCancelled else { return }
        let charted = seaRoutes.track(from: origin, to: destination)
        track = charted
        fit(charted)
        if reduceMotion {
            drawn = 1
            return
        }
        for frame in 1...45 {
            try? await Task.sleep(for: .milliseconds(25))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: 0.025)) { drawn = Double(frame) / 45 }
        }
    }

    /// On the speed step, a ghost ship sails the route at a pace that follows the slider.
    private func sailPreview() async {
        guard step == .speed, !reduceMotion else {
            preview = 0
            return
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(66))
            preview = (preview + knots / 1500).truncatingRemainder(dividingBy: 1)
        }
    }

    private func fit(_ track: VoyageTrack) {
        let rect = track.path.map(MKMapPoint.init).reduce(MKMapRect.null) {
            $0.union(MKMapRect(origin: $1, size: MKMapSize(width: 1, height: 1)))
        }
        withAnimation(reduceMotion ? nil : .smooth(duration: 1)) { camera = .fitting(rect) }
    }

    private func finish() async {
        guard let origin, let destination else { return }
        busy = true
        defer { busy = false }
        do {
            // On a retry after a failed carries row, don't create the voyage twice.
            let voyage: Voyage
            if let created {
                voyage = created
            } else {
                voyage = try await ledger.save(
                    Voyage(voyageId: 0, originPort: origin.name, destPort: destination.name,
                           departDate: APIDate.string(depart), vesselId: vesselId),
                    isNew: true)
                created = voyage
            }
            let existing = Set(ledger.carries.filter { $0.voyageId == voyage.id }.map(\.cargoId))
            for cargoId in cargoIds.sorted() where !existing.contains(cargoId) {
                try await ledger.save(Carries(voyageId: voyage.id, cargoId: cargoId), isNew: true)
            }
            finishes += 1
            onPlotted(voyage)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension Calendar {
    /// Gregorian calendar in GMT, matching how `APIDate` reads stored days.
    static let gmt: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
}
