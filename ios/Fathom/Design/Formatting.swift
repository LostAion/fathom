import SwiftUI

extension Decimal {
    var money: String {
        formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    /// "$50M", "$185K"
    var compactMoney: String {
        formatted(.currency(code: "USD").notation(.compactName).precision(.fractionLength(0...1)))
    }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// "1 policy", "3 policies", "1 treaty share", "2 treaty shares".
nonisolated func counted(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
    "\(count) \(count == 1 ? singular : plural ?? singular + "s")"
}

extension Binding where Value == String? {
    /// Lets a TextField edit an optional column; an empty field saves as null.
    var orEmpty: Binding<String> {
        Binding<String>(
            get: { wrappedValue ?? "" },
            set: { wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}
