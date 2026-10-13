import SwiftUI

/// Create or edit sheet for a Network record. These tables only have a few
/// columns, so a short form is enough here; the larger records get guided flows.
struct NetworkEditor: View {
    let route: NetworkRoute
    @Environment(Ledger.self) private var ledger

    var body: some View {
        let isNew = route.key == nil
        switch route.kind {
        case .client:
            EditSheet(kind: .client, isNew: isNew,
                      item: ledger.clients.first { $0.id == route.key } ?? Client(clientId: 0, name: ""),
                      isValid: { !$0.name.isBlank }) { $client in
                TextField("Name", text: $client.name)
                TextField("Address", text: $client.address.orEmpty, axis: .vertical)
                    // Multi-line fields drop their title from accessibility once they have text.
                    .accessibilityLabel("Address")
                    .accessibilityIdentifier("Address")
            }
        case .broker:
            EditSheet(kind: .broker, isNew: isNew,
                      item: ledger.brokers.first { $0.id == route.key } ?? Broker(brokerId: 0, agencyName: "", licenceNo: ""),
                      isValid: { !$0.agencyName.isBlank && !$0.licenceNo.isBlank }) { $broker in
                TextField("Agency name", text: $broker.agencyName)
                TextField("Licence number", text: $broker.licenceNo)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
            }
        case .underwriter:
            EditSheet(kind: .underwriter, isNew: isNew,
                      item: ledger.underwriters.first { $0.id == route.key } ?? Underwriter(empId: 0, name: ""),
                      isValid: { !$0.name.isBlank }) { $uw in
                TextField("Name", text: $uw.name)
                TextField("Designation", text: $uw.designation.orEmpty)
                Picker("Department", selection: $uw.deptId) {
                    Text("None").tag(Int?.none)
                    ForEach(ledger.departments) { Text($0.name).tag(Optional($0.id)) }
                }
            }
        case .department:
            EditSheet(kind: .department, isNew: isNew,
                      item: ledger.departments.first { $0.id == route.key } ?? Department(deptId: 0, name: ""),
                      isValid: { !$0.name.isBlank }) { $dept in
                TextField("Name", text: $dept.name)
                TextField("Location", text: $dept.location.orEmpty)
            }
        case .surveyor:
            EditSheet(kind: .surveyor, isNew: isNew,
                      item: ledger.surveyors.first { $0.id == route.key } ?? Surveyor(surveyorId: 0, name: ""),
                      isValid: { !$0.name.isBlank }) { $surveyor in
                TextField("Name", text: $surveyor.name)
                TextField("Qualification", text: $surveyor.qualification.orEmpty, axis: .vertical)
                    // Multi-line fields drop their title from accessibility once they have text.
                    .accessibilityLabel("Qualification")
                    .accessibilityIdentifier("Qualification")
            }
        case .reinsurer:
            EditSheet(kind: .reinsurer, isNew: isNew,
                      item: ledger.reinsurers.first { $0.id == route.key } ?? Reinsurer(reinsurerId: 0, name: ""),
                      isValid: { !$0.name.isBlank }) { $reinsurer in
                TextField("Name", text: $reinsurer.name)
            }
        }
    }
}

private extension EditSheet {
    init(kind: NetworkKind, isNew: Bool, item: T, isValid: @escaping (T) -> Bool,
         @ViewBuilder fields: @escaping (Binding<T>) -> Fields) {
        self.init(title: kind.title, symbol: kind.symbol, tint: kind.tint, isNew: isNew, item: item,
                  isValid: isValid, fields: fields)
    }
}
