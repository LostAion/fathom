import SwiftUI

/// Short create/edit form for tables with only a few columns: title, Cancel / Save,
/// server errors and a success haptic. Bigger records use `GuidedFlow` instead.
struct EditSheet<T: APIModel, Fields: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    let isNew: Bool
    let isValid: (T) -> Bool
    var onSaved: ((T) -> Void)?
    let fields: (Binding<T>) -> Fields

    @State private var item: T
    @State private var saving = false
    @State private var error: String?
    @State private var saves = 0
    @Environment(Ledger.self) private var ledger
    @Environment(\.dismiss) private var dismiss

    init(title: String, symbol: String, tint: Color, isNew: Bool, item: T,
         isValid: @escaping (T) -> Bool, onSaved: ((T) -> Void)? = nil,
         @ViewBuilder fields: @escaping (Binding<T>) -> Fields) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.isNew = isNew
        self.isValid = isValid
        self.onSaved = onSaved
        self.fields = fields
        _item = State(initialValue: item)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    fields($item)
                } header: {
                    Label(title, systemImage: symbol)
                        .foregroundStyle(tint)
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.coral)
                    }
                }
            }
            .navigationTitle(isNew ? "New \(title.lowercased())" : "Edit \(title.lowercased())")
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
            let saved = try await ledger.save(item, isNew: isNew)
            saves += 1
            onSaved?(saved)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
