import SwiftUI

/// Edit sheet for an existing policy. New policies go through `IssuePolicyFlow`.
struct PolicyEditor: View {
    let policy: Policy
    @Environment(Ledger.self) private var ledger

    var body: some View {
        let type = policy.policyType ?? .hull
        EditSheet(title: "Policy", symbol: type.symbol, tint: type.tint, isNew: false, item: policy,
                  isValid: Self.isValid) { $item in
            Picker("Client", selection: $item.clientId) {
                Text("None").tag(Int?.none)
                ForEach(ledger.clients) { Text($0.name).tag(Optional($0.id)) }
            }
            Picker("Broker", selection: $item.brokerId) {
                Text("None").tag(Int?.none)
                ForEach(ledger.brokers) { Text($0.agencyName).tag(Optional($0.id)) }
            }
            Picker("Underwriter", selection: $item.empId) {
                Text("None").tag(Int?.none)
                ForEach(ledger.underwriters) { Text($0.name).tag(Optional($0.id)) }
            }
            if type == .cargo {
                Picker("Cargo", selection: $item.cargoId) {
                    Text("None").tag(Int?.none)
                    ForEach(ledger.cargos) { Text($0.description ?? "Cargo #\($0.id)").tag(Optional($0.id)) }
                }
                TextField("Cargo type", text: $item.cargoType.orEmpty)
            } else {
                Picker("Vessel", selection: $item.vesselId) {
                    Text("None").tag(Int?.none)
                    ForEach(ledger.vessels) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            Group {
                DatePicker("Cover starts", selection: $item.issueDate.apiDate, displayedComponents: .date)
                DatePicker("Cover ends", selection: $item.expiryDate.apiDate, displayedComponents: .date)
            }
            .environment(\.timeZone, .gmt)
            MoneyField(title: "Sum insured", text: $item.sumInsured.orEmpty)
            MoneyField(title: "Premium", text: $item.premium.orEmpty)
            MoneyField(title: "Deductible", text: $item.deductible.orEmpty)
            if type == .hull {
                MoneyField(title: "Vessel value covered", text: $item.vesselValueCovered.orEmpty)
            } else if type == .pi {
                MoneyField(title: "Liability limit", text: $item.liabilityLimit.orEmpty)
            }
        }
    }

    private static func isValid(_ policy: Policy) -> Bool {
        guard let issued = policy.issued, let expires = policy.expires, expires > issued else { return false }
        return [policy.premium, policy.sumInsured, policy.deductible].allSatisfy { Decimal(apiString: $0) != nil }
    }
}

private struct MoneyField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        LabeledContent(title) {
            TextField(title, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.rounded(.body))
        }
    }
}

private extension Binding where Value == String? {
    /// Edits a "yyyy-MM-dd" column with a DatePicker.
    var apiDate: Binding<Date> {
        Binding<Date>(
            get: { APIDate.parse(wrappedValue) ?? PolicyMath.today() },
            set: { wrappedValue = APIDate.string($0) }
        )
    }
}
