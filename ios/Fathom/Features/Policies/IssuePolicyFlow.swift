import SwiftUI

/// Guided creation of a new policy. It is saved as a DRAFT; quoting and binding
/// happen later from the policy screen.
struct IssuePolicyFlow: View {
    /// Called with the new policy number after the server saved it.
    let onIssued: (Int) -> Void

    @Environment(Ledger.self) private var ledger
    @State private var clientId: Int?
    @State private var type = PolicyType.hull
    @State private var vesselId: Int?
    @State private var cargoId: Int?
    @State private var cargoType = ""
    @State private var sumPosition = Scales.sumInsured.position(of: 25_000_000)
    @State private var ratePosition = Scales.rate.position(of: 0.25)
    @State private var deductiblePosition = Scales.deductible.position(of: 10_000)
    /// Vessel value covered (hull) or liability limit (P&I). Follows the sum insured until moved.
    @State private var extraPosition: Double?
    @State private var issueDate = PolicyMath.today()
    @State private var expiryDate = PolicyMath.adding(years: 1, to: PolicyMath.today())
    @State private var brokerId: Int?
    @State private var empId: Int?
    @State private var adding: NewRecord?
    /// What was being added and the ids that existed before, so the new row can be picked on return.
    @State private var pending: (record: NewRecord, before: Set<Int>)?

    var body: some View {
        GuidedFlow(title: "New policy", tint: Theme.teal, steps: steps, finishLabel: "Save as draft", onFinish: issue) { step in
            switch step {
            case 0: clientStep
            case 1: typeStep
            case 2: subjectStep
            case 3: amountsStep
            case 4: datesStep
            case 5: partiesStep
            default: reviewStep
            }
        }
        .sheet(item: $adding, onDismiss: selectAdded) { record in
            switch record {
            case .client: NetworkEditor(route: NetworkRoute(kind: .client))
            case .broker: NetworkEditor(route: NetworkRoute(kind: .broker))
            case .underwriter: NetworkEditor(route: NetworkRoute(kind: .underwriter))
            case .vessel: VesselEditor()
            case .cargo: CargoEditor()
            }
        }
    }

    // MARK: - Adding records inline

    private enum NewRecord: Identifiable {
        case client, broker, underwriter, vessel, cargo
        var id: Self { self }
    }

    private func ids(of record: NewRecord) -> [Int] {
        switch record {
        case .client: ledger.clients.map(\.id)
        case .broker: ledger.brokers.map(\.id)
        case .underwriter: ledger.underwriters.map(\.id)
        case .vessel: ledger.vessels.map(\.id)
        case .cargo: ledger.cargos.map(\.id)
        }
    }

    private func add(_ record: NewRecord) {
        pending = (record, Set(ids(of: record)))
        adding = record
    }

    private func selectAdded() {
        guard let pending else { return }
        self.pending = nil
        guard let new = ids(of: pending.record).filter({ !pending.before.contains($0) }).max() else { return }
        withAnimation(.snappy) {
            switch pending.record {
            case .client: clientId = new
            case .broker: brokerId = new
            case .underwriter: empId = new
            case .vessel: vesselId = new
            case .cargo:
                cargoId = new
                cargoType = String((ledger.cargos.first { $0.id == new }?.description ?? "").prefix(50))
            }
        }
    }

    private var steps: [FlowStep] {
        [
            FlowStep(title: "Client", prompt: "Who is being insured?", isComplete: clientId != nil),
            FlowStep(title: "Type", prompt: "What kind of cover?"),
            FlowStep(title: type == .cargo ? "Cargo" : "Vessel",
                     prompt: type == .cargo ? "Which cargo is covered?" : "Which vessel is covered?",
                     isComplete: type == .cargo ? cargoId != nil : vesselId != nil),
            FlowStep(title: "Amounts", prompt: "How much cover, at what price?",
                     isComplete: type != .cargo || !cargoType.isBlank),
            FlowStep(title: "Dates", prompt: "When does cover run?", isComplete: expiryDate > issueDate),
            FlowStep(title: "Parties", prompt: "Who placed and who writes it?", isComplete: brokerId != nil && empId != nil),
            FlowStep(title: "Review", prompt: "Ready to issue?"),
        ]
    }

    // MARK: - Values

    private var sumInsured: Decimal { Scales.sumInsured.roundedValue(at: sumPosition) }
    private var premium: Decimal {
        let rate = Scales.rate.value(at: ratePosition) / 100
        let raw = NSDecimalNumber(decimal: sumInsured).doubleValue * rate
        return min(LogScale.round(raw, digits: 3), 99_900_000)
    }
    private var deductible: Decimal { Scales.deductible.roundedValue(at: deductiblePosition) }
    private var extraValue: Decimal { extraPosition.map { Scales.sumInsured.roundedValue(at: $0) } ?? sumInsured }
    private var rateOnLine: Decimal? { PolicyMath.rateOnLine(premium: premium, sumInsured: sumInsured) }

    private var draft: Policy {
        Policy(
            policyNo: 0,
            issueDate: APIDate.string(issueDate),
            expiryDate: APIDate.string(expiryDate),
            premium: premium.apiString,
            sumInsured: sumInsured.apiString,
            policyType: type,
            vesselValueCovered: type == .hull ? extraValue.apiString : nil,
            cargoType: type == .cargo ? String(cargoType.trimmingCharacters(in: .whitespaces).prefix(50)) : nil,
            liabilityLimit: type == .pi ? extraValue.apiString : nil,
            status: PolicyStatus.draft.rawValue,
            deductible: deductible.apiString,
            clientId: clientId,
            brokerId: brokerId,
            empId: empId,
            vesselId: type == .cargo ? nil : vesselId,
            cargoId: type == .cargo ? cargoId : nil
        )
    }

    private func issue() async throws {
        let saved = try await ledger.save(draft, isNew: true)
        onIssued(saved.policyNo)
    }

    // MARK: - Steps

    private var clientStep: some View {
        VStack(spacing: 12) {
            clientGrid
            AddNewButton(title: "Add a new client") { add(.client) }
        }
    }

    private var clientGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(ledger.clients) { client in
                let selected = client.id == clientId
                Button {
                    withAnimation(.snappy) { clientId = client.id }
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            Monogram(name: client.name, tint: NetworkKind.client.tint, size: 48)
                            Spacer()
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selected ? Theme.teal : Theme.inkMuted.opacity(0.5))
                                .contentTransition(.symbolEffect(.replace))
                        }
                        Text(client.name)
                            .font(.rounded(.headline))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(counted(ledger.policies.count { $0.clientId == client.id }, "policy", "policies"))
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .glassEffect(selected ? .regular.tint(Theme.teal.opacity(0.3)).interactive() : .regular.interactive(),
                             in: .rect(cornerRadius: 22))
                .accessibilityLabel(client.name)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: clientId)
    }

    private var typeStep: some View {
        VStack(spacing: 16) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(PolicyType.allCases) { option in
                        TypeCard(type: option, selected: option == type) {
                            withAnimation(.snappy) { type = option }
                        }
                        .containerRelativeFrame(.horizontal) { width, _ in width * 0.82 }
                        .scrollTransition(.interactive) { effect, phase in
                            effect.scaleEffect(phase.isIdentity ? 1 : 0.9).opacity(phase.isIdentity ? 1 : 0.6)
                        }
                        .id(option)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: Binding(get: { type }, set: { if let new = $0 { type = new } }))
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 24, for: .scrollContent)
            .padding(.horizontal, -20)

            HStack(spacing: 8) {
                ForEach(PolicyType.allCases) { option in
                    Capsule()
                        .fill(option == type ? option.tint : Theme.inkMuted.opacity(0.3))
                        .frame(width: option == type ? 22 : 8, height: 8)
                }
            }
            .accessibilityHidden(true)
        }
        .sensoryFeedback(.selection, trigger: type)
        .onChange(of: type) {
            vesselId = nil
            cargoId = nil
            extraPosition = nil
        }
    }

    @ViewBuilder
    private var subjectStep: some View {
        if type == .cargo {
            VStack(spacing: 12) {
                ForEach(ledger.cargos) { cargo in
                    let selected = cargo.id == cargoId
                    Button {
                        withAnimation(.snappy) {
                            cargoId = cargo.id
                            cargoType = String((cargo.description ?? "").prefix(50))
                        }
                    } label: {
                        HStack(spacing: 14) {
                            PolicyArt(type: .cargo)
                                .frame(width: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cargo.description ?? "Cargo #\(cargo.id)")
                                    .font(.rounded(.headline))
                                    .multilineTextAlignment(.leading)
                                Text(cargo.valueAmount?.money ?? "Value not set")
                                    .font(.rounded(.subheadline))
                                    .foregroundStyle(Theme.inkMuted)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selected ? Theme.teal : Theme.inkMuted.opacity(0.5))
                        }
                        .padding(16)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(selected ? .regular.tint(PolicyType.cargo.tint.opacity(0.25)).interactive() : .regular.interactive(),
                                 in: .rect(cornerRadius: 22))
                    .accessibilityLabel(cargo.description ?? "Cargo \(cargo.id)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                AddNewButton(title: "Add new cargo", tint: PolicyType.cargo.tint) { add(.cargo) }
            }
            .sensoryFeedback(.selection, trigger: cargoId)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(ledger.vessels) { vessel in
                            VesselPassCard(vessel: vessel, selected: vessel.id == vesselId) {
                                withAnimation(.snappy) { vesselId = vessel.id }
                            }
                            .containerRelativeFrame(.horizontal) { width, _ in width * 0.72 }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .padding(.horizontal, -20)
                AddNewButton(title: "Add a new vessel") { add(.vessel) }
            }
            .sensoryFeedback(.selection, trigger: vesselId)
        }
    }

    private var amountsStep: some View {
        VStack(spacing: 14) {
            AmountSlider(title: "Sum insured", value: sumInsured, position: $sumPosition, tint: Theme.teal,
                         caption: "The most this policy pays out.")

            AmountSlider(title: "Premium", value: premium, position: $ratePosition, tint: Theme.amber,
                         caption: nil) {
                HStack {
                    Text("Rate on line")
                        .foregroundStyle(Theme.inkMuted)
                    Spacer()
                    Text(rateOnLine.map(PolicyFormat.percent) ?? "–")
                        .font(.rounded(.headline, weight: .bold))
                        .foregroundStyle(Theme.amber)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("rate-on-line")
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }

            AmountSlider(title: "Deductible", value: deductible, position: $deductiblePosition, tint: Theme.coral,
                         caption: "Taken off every claim before it pays.")

            switch type {
            case .hull:
                AmountSlider(title: "Vessel value covered", value: extraValue, position: extraBinding, tint: PolicyType.hull.tint,
                             caption: "Starts at the sum insured.")
            case .pi:
                AmountSlider(title: "Liability limit", value: extraValue, position: extraBinding, tint: PolicyType.pi.tint,
                             caption: "Starts at the sum insured.")
            case .cargo:
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cargo type")
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.inkMuted)
                        TextField("Cargo type", text: $cargoType)
                            .font(.rounded(.headline))
                            .onChange(of: cargoType) { if cargoType.count > 50 { cargoType = String(cargoType.prefix(50)) } }
                        Text("Taken from the cargo description. Up to 50 characters.")
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
            }
        }
    }

    private var extraBinding: Binding<Double> {
        Binding(get: { extraPosition ?? sumPosition }, set: { extraPosition = $0 })
    }

    private var datesStep: some View {
        DatesPicker(issueDate: $issueDate, expiryDate: $expiryDate)
    }

    private var partiesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Broker")
            ForEach(ledger.brokers) { broker in
                PickRow(name: broker.agencyName, subtitle: broker.licenceNo, monospaced: true,
                        kind: .broker, selected: broker.id == brokerId) {
                    withAnimation(.snappy) { brokerId = broker.id }
                }
            }
            AddNewButton(title: "Add a new broker", tint: NetworkKind.broker.tint) { add(.broker) }
            SectionHeader(title: "Underwriter")
                .padding(.top, 8)
            ForEach(ledger.underwriters) { uw in
                PickRow(name: uw.name, subtitle: uw.designation, monospaced: false,
                        kind: .underwriter, selected: uw.id == empId) {
                    withAnimation(.snappy) { empId = uw.id }
                }
            }
            AddNewButton(title: "Add a new underwriter", tint: NetworkKind.underwriter.tint) { add(.underwriter) }
        }
        .sensoryFeedback(.selection, trigger: brokerId)
        .sensoryFeedback(.selection, trigger: empId)
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            PolicyCard(policy: draft, clientName: ledger.clients.first { $0.id == clientId }?.name)
                .allowsHitTesting(false)
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    reviewLine("Subject", type == .cargo
                               ? ledger.cargos.first { $0.id == cargoId }?.description
                               : ledger.vessels.first { $0.id == vesselId }?.name, id: "review-subject")
                    Divider()
                    reviewLine("Sum insured", sumInsured.money, id: "review-sum-insured")
                    reviewLine("Premium", premium.money, id: "review-premium")
                    reviewLine("Rate on line", rateOnLine.map(PolicyFormat.percent), id: "review-rate")
                    reviewLine("Deductible", deductible.money, id: "review-deductible")
                    if let extra = draft.typeSpecific {
                        reviewLine(extra.label, extra.value, id: "review-extra")
                    }
                    Divider()
                    reviewLine("Cover", "\(PolicyFormat.day(issueDate)) → \(PolicyFormat.day(expiryDate))", id: "review-dates")
                    reviewLine("Broker", ledger.brokers.first { $0.id == brokerId }?.agencyName, id: "review-broker")
                    reviewLine("Underwriter", ledger.underwriters.first { $0.id == empId }?.name, id: "review-underwriter")
                }
            }
            Label("Saved as a draft. Quote and bind it from the policy screen.", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(Theme.inkMuted)
        }
    }

    private func reviewLine(_ label: String, _ value: String?, id: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(Theme.inkMuted)
            Spacer(minLength: 12)
            Text(value ?? "–")
                .font(.rounded(.body, weight: .semibold))
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "Not set")
        .accessibilityIdentifier(id)
    }
}

/// Slider ranges. Premium is set as a rate so it keeps its proportion when the sum insured moves.
private enum Scales {
    static let sumInsured = LogScale(lower: 100_000, upper: 2_000_000_000)
    /// Percent of the sum insured.
    static let rate = LogScale(lower: 0.01, upper: 10)
    static let deductible = LogScale(lower: 1_000, upper: 2_000_000)
}

// MARK: - Pieces

private struct TypeCard: View {
    let type: PolicyType
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                PolicyArt(type: type)
                    .frame(maxWidth: .infinity, maxHeight: 130)
                    .padding(.vertical, 8)
                Label(type.displayName, systemImage: type.symbol)
                    .font(.rounded(.title3, weight: .bold))
                    .foregroundStyle(type.tint)
                Text(blurb)
                    .font(.callout)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(selected ? type.tint : Theme.inkMuted.opacity(0.5))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [type.tint.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom),
                        in: .rect(cornerRadius: 26))
            .contentShape(.rect(cornerRadius: 26))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
        .accessibilityLabel(type.displayName)
        .accessibilityHint(blurb)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var blurb: String {
        switch type {
        case .hull: "Physical loss or damage to the ship and its machinery."
        case .cargo: "Goods in transit, from loading to discharge."
        case .pi: "Third party liability: crew, pollution, collision and wreck removal."
        }
    }
}

/// Vessel "passport" in the subject carousel.
private struct VesselPassCard: View {
    let vessel: Vessel
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                PolicyArt(type: .hull)
                    .frame(maxWidth: .infinity, maxHeight: 90)
                HStack(alignment: .firstTextBaseline) {
                    Text(vessel.name)
                        .font(.rounded(.headline))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? Theme.teal : Theme.inkMuted.opacity(0.5))
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(vessel.imoNumber)
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.inkMuted)
                HStack(spacing: 12) {
                    if let flag = vessel.flag {
                        Label(flag, systemImage: "flag.fill")
                    }
                    if let tonnage = vessel.tonnage {
                        Label("\(tonnage.formatted()) t", systemImage: "scalemass.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
            }
            .padding(16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(Theme.teal.opacity(0.3)).interactive() : .regular.interactive(),
                     in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(vessel.name)
        .accessibilityValue([vessel.imoNumber, vessel.flag].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { action() }
    }
}

/// A money amount with a log-scale slider under it.
private struct AmountSlider<Footer: View>: View {
    let title: String
    let value: Decimal
    @Binding var position: Double
    let tint: Color
    let caption: String?
    @ViewBuilder var footer: Footer

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.inkMuted)
                    Spacer()
                    Text(value.compactMoney)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Text(value.money)
                    .font(.rounded(.title, weight: .bold))
                    .contentTransition(.numericText(value: NSDecimalNumber(decimal: value).doubleValue))
                    .animation(.snappy, value: value)
                    .accessibilityHidden(true)
                Slider(value: $position, in: 0...1)
                    .tint(tint)
                    .accessibilityLabel(title)
                    .accessibilityValue(value.money)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                footer
            }
        }
    }
}

private extension AmountSlider where Footer == EmptyView {
    init(title: String, value: Decimal, position: Binding<Double>, tint: Color, caption: String?) {
        self.init(title: title, value: value, position: position, tint: tint, caption: caption) { EmptyView() }
    }
}

/// Cover start and end on one graphical calendar, switched with a segmented control.
private struct DatesPicker: View {
    @Binding var issueDate: Date
    @Binding var expiryDate: Date
    @State private var editingEnd = false

    var body: some View {
        VStack(spacing: 14) {
            GlassCard {
                HStack {
                    end("Cover starts", issueDate, active: !editingEnd) { editingEnd = false }
                    Image(systemName: "arrow.right")
                        .foregroundStyle(Theme.inkMuted)
                    end("Cover ends", expiryDate, active: editingEnd) { editingEnd = true }
                }
                Text(length)
                    .font(.rounded(.subheadline, weight: .semibold))
                    .foregroundStyle(expiryDate > issueDate ? Theme.teal : Theme.coral)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }
            GlassCard {
                Group {
                    if editingEnd {
                        DatePicker("Cover ends", selection: $expiryDate,
                                   in: PolicyMath.adding(days: 1, to: issueDate)...,
                                   displayedComponents: .date)
                    } else {
                        DatePicker("Cover starts", selection: $issueDate, displayedComponents: .date)
                    }
                }
                .datePickerStyle(.graphical)
                .tint(Theme.teal)
                .environment(\.timeZone, .gmt)
            }
        }
        .onChange(of: issueDate) {
            if expiryDate <= issueDate { expiryDate = PolicyMath.adding(years: 1, to: issueDate) }
        }
        .sensoryFeedback(.selection, trigger: editingEnd)
    }

    private var length: String {
        let days = PolicyMath.days(from: issueDate, to: expiryDate)
        return days > 0 ? "\(counted(days, "day")) of cover" : "Cover must end after it starts"
    }

    private func end(_ label: String, _ date: Date, active: Bool, select: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { select() }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(active ? Theme.teal : Theme.inkMuted)
                Text(PolicyFormat.day(date))
                    .font(.rounded(.headline))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(active ? Theme.teal.opacity(0.14) : .clear, in: .rect(cornerRadius: 14))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(PolicyFormat.day(date))
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// A person or organisation to pick in a flow.
private struct PickRow: View {
    let name: String
    let subtitle: String?
    let monospaced: Bool
    let kind: NetworkKind
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Monogram(name: name, tint: kind.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.rounded(.headline))
                    if let subtitle {
                        Text(subtitle)
                            .font(monospaced ? .caption.monospaced() : .caption)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? kind.tint : Theme.inkMuted.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(kind.tint.opacity(0.28)).interactive() : .regular.interactive(),
                     in: .rect(cornerRadius: 20))
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
