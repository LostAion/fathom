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

/// Shared sheet chrome: title, Cancel / Save, server errors, success haptic.
private struct EditSheet<T: APIModel, Fields: View>: View {
    let kind: NetworkKind
    let isNew: Bool
    let isValid: (T) -> Bool
    let fields: (Binding<T>) -> Fields

    @State private var item: T
    @State private var saving = false
    @State private var error: String?
    @State private var saves = 0
    @Environment(Ledger.self) private var ledger
    @Environment(\.dismiss) private var dismiss

    init(kind: NetworkKind, isNew: Bool, item: T, isValid: @escaping (T) -> Bool,
         @ViewBuilder fields: @escaping (Binding<T>) -> Fields) {
        self.kind = kind
        self.isNew = isNew
        self.isValid = isValid
        self.fields = fields
        _item = State(initialValue: item)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    fields($item)
                } header: {
                    Label(kind.title, systemImage: kind.symbol)
                        .foregroundStyle(kind.tint)
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.coral)
                    }
                }
            }
            .navigationTitle(isNew ? "New \(kind.rawValue)" : "Edit \(kind.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") { Task { await save() } }
                        .disabled(!isValid(item) || saving)
                }
            }
            .disabled(saving)
        }
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.success, trigger: saves)
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await ledger.save(item, isNew: isNew)
            saves += 1
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
