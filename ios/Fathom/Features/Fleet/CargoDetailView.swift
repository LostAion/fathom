import SwiftUI

/// A consignment, the voyages carrying it and the policies that insure it.
struct CargoDetailView: View {
    let cargoId: Int

    @Environment(Ledger.self) private var ledger
    @State private var editing = false

    private var cargo: Cargo? { ledger.cargos.first { $0.id == cargoId } }

    var body: some View {
        DetailPage {
            if let cargo {
                let voyageIDs = Set(ledger.carries.filter { $0.cargoId == cargo.id }.map(\.voyageId))
                let voyages = ledger.voyages.filter { voyageIDs.contains($0.id) }
                let policies = ledger.policies.filter { $0.cargoId == cargo.id }
                hero(cargo)

                SectionHeader(title: "Carried on", count: voyages.count)
                if voyages.isEmpty { NoneYet(text: "Not on a voyage. Load it from a voyage screen.") }
                ForEach(voyages) { VoyageLink(voyage: $0) }

                SectionHeader(title: "Policies insuring it", count: policies.count)
                if policies.isEmpty { NoneYet() }
                ForEach(policies) { policy in
                    NavigationLink(value: AppRoute.policy(policy.policyNo)) { PolicyRow(policy: policy) }
                        .buttonStyle(.plain)
                }
            } else {
                ContentUnavailableView("Cargo removed", systemImage: "shippingbox")
            }
        }
        .navigationTitle("Cargo #\(cargoId)")
        .modifier(CargoActions(cargo: cargo, editing: $editing))
        .sheet(isPresented: $editing) {
            if let cargo { CargoEditor(cargo: cargo) }
        }
    }

    private func hero(_ cargo: Cargo) -> some View {
        GlassCard(tint: Theme.amber) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.amber)
                    .frame(width: 64, height: 64)
                    .background(Theme.amber.opacity(0.16), in: .rect(cornerRadius: 18))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Label("Cargo", systemImage: "shippingbox")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.amber)
                    Text(cargo.description ?? "Cargo #\(cargo.id)")
                        .font(.rounded(.title3, weight: .bold))
                    Text(cargo.valueAmount?.money ?? "No value declared")
                        .font(.rounded(.title, weight: .bold))
                        .contentTransition(.numericText())
                    Text("Declared value · ID #\(cargo.id)")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CargoActions: ViewModifier {
    let cargo: Cargo?
    @Binding var editing: Bool
    @Environment(Ledger.self) private var ledger

    func body(content: Content) -> some View {
        let links = ledger.carries.count { $0.cargoId == cargo?.id }
        let notes = [
            links == 0 ? nil : "\(counted(links, "voyage link")) will be deleted too (ON DELETE CASCADE).",
            unlinkNote(ledger.policies.count { $0.cargoId == cargo?.id }, "policy", "policies", losing: "cargo"),
        ].compactMap { $0 }
        content.recordActions(
            available: cargo != nil, name: cargo?.description ?? "cargo", deleteLabel: "Delete cargo",
            effect: notes.isEmpty ? "No voyages or policies are linked to this cargo." : notes.joined(separator: " "),
            editing: $editing
        ) { if let cargo { try await ledger.delete(cargo) } }
    }
}
