import SwiftUI

/// Profile card for one person or organisation, with the records linked to it.
struct NetworkProfileView: View {
    let route: NetworkRoute

    @Environment(Ledger.self) private var ledger
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var deleteError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let record {
                    header(record)
                    facts(record.facts)
                    linked
                } else {
                    ContentUnavailableView("Record removed", systemImage: route.kind.symbol)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .foregroundStyle(Theme.ink)
        .background { SonarBackground() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if record != nil {
                ToolbarItem {
                    Button("Edit") { editing = true }
                }
                ToolbarItem {
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .sheet(isPresented: $editing) { NetworkEditor(route: route) }
        .confirmationDialog("Delete \(record?.name ?? "")?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete \(route.kind.rawValue)", role: .destructive) {
                Task {
                    do {
                        try await record?.delete()
                        dismiss()
                    } catch {
                        deleteError = error.localizedDescription
                    }
                }
            }
        } message: {
            Text(record?.deleteEffect ?? "")
        }
        .alert("Couldn't delete", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK") {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    // MARK: - Layout

    private func header(_ record: Record) -> some View {
        GlassCard(tint: route.kind.tint) {
            HStack(spacing: 16) {
                Monogram(name: record.name, tint: route.kind.tint, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Label(route.kind.title, systemImage: route.kind.symbol)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(route.kind.tint)
                    Text(record.name)
                        .font(.rounded(.title2, weight: .bold))
                    if let stat = record.stat {
                        Text(stat)
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
            }
        }
    }

    private func facts(_ facts: [Fact]) -> some View {
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

    @ViewBuilder
    private var linked: some View {
        switch route.kind {
        case .client:
            policyList(ledger.policies.filter { $0.clientId == route.key })
        case .broker:
            policyList(ledger.policies.filter { $0.brokerId == route.key }, title: "Policies placed")
        case .underwriter:
            policyList(ledger.policies.filter { $0.empId == route.key }, title: "Policies written")
        case .department:
            let members = ledger.underwriters.filter { $0.deptId == route.key }
            SectionHeader(title: "Underwriters", count: members.count)
            ForEach(members) { uw in
                NavigationLink(value: NetworkRoute(kind: .underwriter, key: uw.id)) {
                    DirectoryRow(name: uw.name, subtitle: uw.designation, kind: .underwriter,
                                 stat: "\(ledger.policies.count { $0.empId == uw.id })", statLabel: "written")
                }
                .buttonStyle(.plain)
            }
        case .surveyor:
            let claimIDs = Set(ledger.assessedBy.filter { $0.surveyorId == route.key }.map(\.claimId))
            let claims = ledger.claims.filter { claimIDs.contains($0.claimId) }
            SectionHeader(title: "Claims surveyed", count: claims.count)
            ForEach(claims) { claim in
                NavigationLink(value: AppRoute.claim(claim.claimId)) { ClaimRow(claim: claim) }
                    .buttonStyle(.plain)
            }
        case .reinsurer:
            let shares = ledger.reinsuredBy.filter { $0.reinsurerId == route.key }
            SectionHeader(title: "Treaty shares", count: shares.count)
            ForEach(shares) { share in
                if let policy = ledger.policies.first(where: { $0.policyNo == share.policyNo }) {
                    NavigationLink(value: AppRoute.policy(policy.policyNo)) {
                        PolicyRow(policy: policy, detail: "\(share.share?.formatted() ?? "–")% share")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func policyList(_ policies: [Policy], title: String = "Policies") -> some View {
        SectionHeader(title: title, count: policies.count)
        if policies.isEmpty {
            Text("None yet")
                .font(.callout)
                .foregroundStyle(Theme.inkMuted)
        }
        ForEach(policies) { policy in
            NavigationLink(value: AppRoute.policy(policy.policyNo)) { PolicyRow(policy: policy) }
                .buttonStyle(.plain)
        }
    }

    // MARK: - Record

    private struct Fact {
        var label: String
        var value: String?
        var monospaced = false
    }

    private struct Record {
        var name: String
        var stat: String?
        var facts: [Fact]
        /// What the foreign keys do to linked rows, shown before deleting.
        var deleteEffect: String
        var delete: () async throws -> Void
    }

    private var record: Record? {
        let key = route.key
        switch route.kind {
        case .client:
            guard let client = ledger.clients.first(where: { $0.id == key }) else { return nil }
            let policies = ledger.policies.filter { $0.clientId == client.id }
            return Record(
                name: client.name,
                stat: policies.isEmpty ? "No policies yet" : "\(policies.compactMap(\.sumInsuredAmount).reduce(0, +).money) insured",
                facts: [Fact(label: "Client ID", value: "#\(client.id)", monospaced: true),
                        Fact(label: "Address", value: client.address)],
                deleteEffect: unlinkMessage(policies.count),
                delete: { try await ledger.delete(client) }
            )
        case .broker:
            guard let broker = ledger.brokers.first(where: { $0.id == key }) else { return nil }
            let policies = ledger.policies.filter { $0.brokerId == broker.id }
            return Record(
                name: broker.agencyName,
                stat: "\(policies.compactMap(\.premiumAmount).reduce(0, +).money) premium placed",
                facts: [Fact(label: "Licence", value: broker.licenceNo, monospaced: true),
                        Fact(label: "Broker ID", value: "#\(broker.id)", monospaced: true)],
                deleteEffect: unlinkMessage(policies.count),
                delete: { try await ledger.delete(broker) }
            )
        case .underwriter:
            guard let uw = ledger.underwriters.first(where: { $0.id == key }) else { return nil }
            let dept = ledger.departments.first { $0.id == uw.deptId }
            return Record(
                name: uw.name,
                stat: uw.designation,
                facts: [Fact(label: "Department", value: dept?.name),
                        Fact(label: "Location", value: dept?.location),
                        Fact(label: "Employee ID", value: "#\(uw.id)", monospaced: true)],
                deleteEffect: unlinkMessage(ledger.policies.count { $0.empId == uw.id }),
                delete: { try await ledger.delete(uw) }
            )
        case .department:
            guard let dept = ledger.departments.first(where: { $0.id == key }) else { return nil }
            let members = ledger.underwriters.count { $0.deptId == dept.id }
            return Record(
                name: dept.name,
                stat: counted(members, "underwriter"),
                facts: [Fact(label: "Location", value: dept.location),
                        Fact(label: "Department ID", value: "#\(dept.id)", monospaced: true)],
                deleteEffect: members == 0 ? "No underwriters are in this department." : "\(counted(members, "underwriter")) will stay on file with no department (ON DELETE SET NULL).",
                delete: { try await ledger.delete(dept) }
            )
        case .surveyor:
            guard let surveyor = ledger.surveyors.first(where: { $0.id == key }) else { return nil }
            let surveys = ledger.assessedBy.count { $0.surveyorId == surveyor.id }
            return Record(
                name: surveyor.name,
                stat: "\(counted(surveys, "claim")) surveyed",
                facts: [Fact(label: "Qualification", value: surveyor.qualification),
                        Fact(label: "Surveyor ID", value: "#\(surveyor.id)", monospaced: true)],
                deleteEffect: surveys == 0 ? "No claims are assigned to this surveyor." : "\(counted(surveys, "survey assignment")) will be deleted too (ON DELETE CASCADE). The claims stay.",
                delete: { try await ledger.delete(surveyor) }
            )
        case .reinsurer:
            guard let reinsurer = ledger.reinsurers.first(where: { $0.id == key }) else { return nil }
            let shares = ledger.reinsuredBy.count { $0.reinsurerId == reinsurer.id }
            return Record(
                name: reinsurer.name,
                stat: counted(shares, "treaty share"),
                facts: [Fact(label: "Reinsurer ID", value: "#\(reinsurer.id)", monospaced: true)],
                deleteEffect: shares == 0 ? "No policies are reinsured by them." : "\(counted(shares, "treaty share")) will be deleted too (ON DELETE CASCADE). The policies stay.",
                delete: { try await ledger.delete(reinsurer) }
            )
        }
    }

    private func unlinkMessage(_ policies: Int) -> String {
        policies == 0
            ? "No policies are linked to this record."
            : "\(counted(policies, "linked policy", "linked policies")) will stay on file but lose this link (ON DELETE SET NULL)."
    }
}
