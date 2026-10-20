import SwiftUI

/// A vessel's passport, the policies that cover her and the voyages she makes.
struct VesselDetailView: View {
    let vesselId: Int

    @Environment(Ledger.self) private var ledger
    @State private var editing = false

    private var vessel: Vessel? { ledger.vessels.first { $0.id == vesselId } }

    var body: some View {
        DetailPage {
            if let vessel {
                let policies = ledger.policies.filter { $0.vesselId == vessel.id }
                let voyages = ledger.voyages.filter { $0.vesselId == vessel.id }
                    .sorted { ($0.departDate ?? "") > ($1.departDate ?? "") }
                PassportCard(vessel: vessel, policies: policies.count { $0.isInForce }, voyages: voyages.count, large: true)
                FactsCard(facts: [
                    FleetFact(label: "IMO number", value: vessel.imoNumber, monospaced: true),
                    FleetFact(label: "Gross tonnage", value: vessel.tonnage.map { "\($0.formatted()) GT" }),
                    FleetFact(label: "Flag state", value: vessel.flag.map { "\(vessel.flagEmoji ?? "") \($0)" }),
                    FleetFact(label: "Vessel ID", value: "#\(vessel.id)", monospaced: true),
                ])

                SectionHeader(title: "Policies covering her", count: policies.count)
                if policies.isEmpty { NoneYet() }
                ForEach(policies) { policy in
                    NavigationLink(value: AppRoute.policy(policy.policyNo)) { PolicyRow(policy: policy) }
                        .buttonStyle(.plain)
                }

                SectionHeader(title: "Voyages", count: voyages.count)
                if voyages.isEmpty { NoneYet(text: "No voyages plotted") }
                ForEach(voyages) { VoyageLink(voyage: $0) }
            } else {
                ContentUnavailableView("Vessel removed", systemImage: "ferry")
            }
        }
        .navigationTitle(vessel?.name ?? "Vessel")
        .modifier(VesselActions(vessel: vessel, editing: $editing))
        .sheet(isPresented: $editing) {
            if let vessel { VesselEditor(vessel: vessel) }
        }
    }
}

private struct VesselActions: ViewModifier {
    let vessel: Vessel?
    @Binding var editing: Bool
    @Environment(Ledger.self) private var ledger

    func body(content: Content) -> some View {
        let notes = [
            unlinkNote(ledger.policies.count { $0.vesselId == vessel?.id }, "policy", "policies", losing: "vessel"),
            unlinkNote(ledger.voyages.count { $0.vesselId == vessel?.id }, "voyage", "voyages", losing: "vessel"),
        ].compactMap { $0 }
        content.recordActions(
            available: vessel != nil, name: vessel?.name ?? "vessel", deleteLabel: "Delete vessel",
            effect: notes.isEmpty ? "No policies or voyages are linked to this vessel." : notes.joined(separator: " "),
            editing: $editing
        ) { if let vessel { try await ledger.delete(vessel) } }
    }
}
