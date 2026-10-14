import SwiftUI

/// Add or edit a vessel. A new vessel passes nil.
struct VesselEditor: View {
    var vessel: Vessel?
    var onSaved: ((Vessel) -> Void)?

    var body: some View {
        EditSheet(title: "Vessel", symbol: "ferry.fill", tint: Theme.sky, isNew: vessel == nil,
                  item: vessel ?? Vessel(vesselId: 0, name: "", imoNumber: ""),
                  isValid: { !$0.name.isBlank && !$0.imoNumber.isBlank }, onSaved: onSaved) { $vessel in
            TextField("Name", text: $vessel.name)
            TextField("IMO number", text: $vessel.imoNumber)
                .font(.body.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            TextField("Tonnage (GT)", value: $vessel.tonnage, format: .number)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("Tonnage")
            FlagPicker(flag: $vessel.flag)
        }
    }
}

private struct FlagPicker: View {
    @Binding var flag: String?

    var body: some View {
        Picker(selection: $flag) {
            Text("None").tag(String?.none)
            if let flag, !FlagState.countries.contains(where: { $0.name == flag }) {
                Text(flag).tag(Optional(flag))
            }
            Section("Common registries") {
                ForEach(FlagState.popular, id: \.self) { name in
                    Text("\(FlagState.emoji(for: name) ?? "") \(name)").tag(Optional(name))
                }
            }
            Section("All countries") {
                ForEach(FlagState.countries.filter { !FlagState.popular.contains($0.name) }, id: \.code) { country in
                    Text("\(FlagState.emoji(regionCode: country.code)) \(country.name)").tag(Optional(country.name))
                }
            }
        } label: {
            Text("Flag")
        }
        .pickerStyle(.navigationLink)
    }
}

/// Add or edit a cargo consignment.
struct CargoEditor: View {
    var cargo: Cargo?
    var onSaved: ((Cargo) -> Void)?

    var body: some View {
        EditSheet(title: "Cargo", symbol: "shippingbox.fill", tint: Theme.amber, isNew: cargo == nil,
                  item: cargo ?? Cargo(cargoId: 0),
                  isValid: { !($0.description ?? "").isBlank }, onSaved: onSaved) { $cargo in
            TextField("Description", text: $cargo.description.orEmpty, axis: .vertical)
                // Multi-line fields drop their title from accessibility once they have text.
                .accessibilityLabel("Description")
                .accessibilityIdentifier("Description")
            TextField("Value (USD)", value: $cargo.value.decimal, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("Value")
        }
    }
}

/// Edit a voyage's ports, date and vessel. New voyages use the Plot Voyage flow.
struct VoyageEditor: View {
    let voyage: Voyage
    @Environment(Ledger.self) private var ledger

    var body: some View {
        EditSheet(title: "Voyage", symbol: "point.topleft.down.to.point.bottomright.curvepath", tint: Theme.teal,
                  isNew: false, item: voyage,
                  isValid: { !($0.originPort ?? "").isBlank && !($0.destPort ?? "").isBlank && $0.originPort != $0.destPort }) { $voyage in
            PortPicker(title: "Origin", name: $voyage.originPort)
            PortPicker(title: "Destination", name: $voyage.destPort)
            DatePicker("Departs", selection: $voyage.departDate.day, displayedComponents: .date)
                .environment(\.timeZone, .gmt)
            Picker("Vessel", selection: $voyage.vesselId) {
                Text("None").tag(Int?.none)
                ForEach(ledger.vessels.sorted { $0.name < $1.name }) { vessel in
                    Text("\(vessel.flagEmoji ?? "🚢") \(vessel.name)").tag(Optional(vessel.id))
                }
            }
        }
    }
}

private struct PortPicker: View {
    let title: String
    @Binding var name: String?

    var body: some View {
        Picker(title, selection: $name) {
            if let name, PortCatalog.named(name) == nil {
                Text("📍 \(name)").tag(Optional(name))
            }
            ForEach(PortCatalog.all) { port in
                Text("\(port.flag) \(port.name)").tag(Optional(port.name))
            }
        }
        .pickerStyle(.navigationLink)
    }
}

extension Binding where Value == String? {
    /// Decimal view of a money column stored as a string.
    var decimal: Binding<Decimal?> {
        Binding<Decimal?>(
            get: { Decimal(apiString: wrappedValue) },
            set: { wrappedValue = $0?.apiString }
        )
    }

    /// Date view of a `yyyy-MM-dd` column; empty means tomorrow.
    var day: Binding<Date> {
        Binding<Date>(
            get: { APIDate.parse(wrappedValue) ?? Calendar.current.date(byAdding: .day, value: 1, to: .now)! },
            set: { wrappedValue = APIDate.string($0) }
        )
    }
}
