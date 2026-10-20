import SwiftUI

struct NetworkView: View {
    @Environment(Ledger.self) private var ledger
    @State private var segment = NetworkKind.client
    @State private var search = ""
    @State private var creating: NetworkRoute?

    var body: some View {
        NavigationStack {
            Screen(title: "Network", subtitle: "Clients, brokers and partners") {
                SegmentChips(selection: $segment, count: count(of:))
                SearchField(text: $search, prompt: "Search \(segment.plural.lowercased())")
                LedgerStatusCard()
                directory
                    .animation(.snappy, value: segment)
            }
            .refreshable { await ledger.refresh() }
            .overlay(alignment: .bottomTrailing) { addButton }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: NetworkRoute.self) { NetworkProfileView(route: $0) }
            .appRoutes()
            .sheet(item: $creating) { NetworkEditor(route: $0) }
        }
    }

    // MARK: - Directory

    @ViewBuilder
    private var directory: some View {
        switch segment {
        case .client:
            rows(ledger.clients.filter { matches($0.name) }) { client in
                let policies = ledger.policies.filter { $0.clientId == client.id }
                return DirectoryRow(
                    name: client.name, subtitle: client.address, kind: .client,
                    stat: policies.isEmpty ? nil : policies.compactMap(\.sumInsuredAmount).reduce(0, +).compactMoney,
                    statLabel: "insured"
                )
            }
        case .broker:
            rows(ledger.brokers.filter { matches($0.agencyName) }) { broker in
                DirectoryRow(
                    name: broker.agencyName, subtitle: broker.licenceNo, monospacedSubtitle: true, kind: .broker,
                    stat: "\(ledger.policies.count { $0.brokerId == broker.id })", statLabel: "placed"
                )
            }
        case .underwriter:
            underwritersByDepartment
        case .surveyor:
            rows(ledger.surveyors.filter { matches($0.name) }) { surveyor in
                DirectoryRow(
                    name: surveyor.name, subtitle: surveyor.qualification, kind: .surveyor,
                    stat: "\(ledger.assessedBy.count { $0.surveyorId == surveyor.id })", statLabel: "surveys"
                )
            }
        case .reinsurer:
            rows(ledger.reinsurers.filter { matches($0.name) }) { reinsurer in
                let shares = ledger.reinsuredBy.filter { $0.reinsurerId == reinsurer.id }
                return DirectoryRow(
                    name: reinsurer.name, subtitle: counted(shares.count, "treaty share"), kind: .reinsurer,
                    stat: exposure(of: shares).compactMoney, statLabel: "exposure"
                )
            }
        case .department:
            EmptyView()
        }
    }

    private var underwritersByDepartment: some View {
        let underwriters = ledger.underwriters.filter { matches($0.name) }
        let groups: [(Department?, [Underwriter])] =
            ledger.departments.map { dept in (dept, underwriters.filter { $0.deptId == dept.id }) }
            + [(nil, underwriters.filter { uw in !ledger.departments.contains { $0.id == uw.deptId } })]

        return VStack(alignment: .leading, spacing: 12) {
            ForEach(groups.filter { $0.0 != nil || !$0.1.isEmpty }, id: \.0?.id) { dept, members in
                if let dept {
                    NavigationLink(value: NetworkRoute(kind: .department, key: dept.id)) {
                        HStack {
                            SectionHeader(title: dept.name, count: members.count)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.inkMuted)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    SectionHeader(title: "No department", count: members.count)
                }
                rows(members) { uw in
                    DirectoryRow(
                        name: uw.name, subtitle: uw.designation, kind: .underwriter,
                        stat: "\(ledger.policies.count { $0.empId == uw.id })", statLabel: "written"
                    )
                }
            }
        }
    }

    private func rows<T: APIModel>(_ items: [T], row: @escaping (T) -> DirectoryRow) -> some View where T.ID == Int {
        VStack(spacing: 10) {
            if items.isEmpty && ledger.hasLoaded && segment != .underwriter {
                GlassCard {
                    Label(search.isEmpty ? "No \(segment.plural.lowercased()) yet" : "No matches",
                          systemImage: segment.symbol)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            ForEach(items) { item in
                NavigationLink(value: NetworkRoute(kind: row(item).kind, key: item.id)) {
                    row(item)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private var addButton: some View {
        Group {
            if segment == .underwriter {
                Menu {
                    Button("New underwriter", systemImage: NetworkKind.underwriter.symbol) {
                        creating = NetworkRoute(kind: .underwriter)
                    }
                    Button("New department", systemImage: NetworkKind.department.symbol) {
                        creating = NetworkRoute(kind: .department)
                    }
                } label: {
                    Label("New", systemImage: "plus")
                }
            } else {
                Button("New \(segment.rawValue)", systemImage: "plus") {
                    creating = NetworkRoute(kind: segment)
                }
            }
        }
        .font(.rounded(.headline))
        .buttonStyle(.glassProminent)
        .tint(segment.tint)
        .padding(20)
    }

    // MARK: - Helpers

    private func count(of kind: NetworkKind) -> Int {
        switch kind {
        case .client: ledger.clients.count
        case .broker: ledger.brokers.count
        case .underwriter: ledger.underwriters.count
        case .department: ledger.departments.count
        case .surveyor: ledger.surveyors.count
        case .reinsurer: ledger.reinsurers.count
        }
    }

    private func matches(_ name: String) -> Bool {
        search.isBlank || name.localizedCaseInsensitiveContains(search.trimmingCharacters(in: .whitespaces))
    }

    /// Sum of each share percentage applied to the policy's sum insured.
    private func exposure(of shares: [ReinsuredBy]) -> Decimal {
        shares.reduce(0) { total, share in
            let insured = ledger.policies.first { $0.policyNo == share.policyNo }?.sumInsuredAmount ?? 0
            return total + insured * (share.share ?? 0) / 100
        }
    }
}

// MARK: - Pieces

struct DirectoryRow: View {
    let name: String
    let subtitle: String?
    var monospacedSubtitle = false
    let kind: NetworkKind
    let stat: String?
    let statLabel: String

    var body: some View {
        HStack(spacing: 14) {
            Monogram(name: name, tint: kind.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.rounded(.headline))
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(monospacedSubtitle ? .caption.monospaced() : .caption)
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let stat {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(stat)
                        .font(.rounded(.headline, weight: .semibold))
                        .contentTransition(.numericText())
                    Text(statLabel)
                        .font(.caption2)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
        }
        .padding(14)
        .contentShape(.rect)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

private struct SegmentChips: View {
    @Binding var selection: NetworkKind
    let count: (NetworkKind) -> Int

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(NetworkKind.segments) { kind in
                        let selected = kind == selection
                        Button {
                            withAnimation(.snappy) { selection = kind }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: kind.symbol)
                                Text(kind.plural)
                                Text("\(count(kind))")
                                    .foregroundStyle(selected ? kind.tint : Theme.inkMuted)
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(selected ? .regular.tint(kind.tint.opacity(0.3)).interactive() : .regular.interactive(), in: .capsule)
                        .accessibilityLabel(kind.plural)
                        .accessibilityValue("\(count(kind))")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private struct SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.inkMuted)
            TextField(prompt, text: $text)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
    }
}
