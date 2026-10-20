import SwiftUI

/// The people and organisations shown in the Network tab.
enum NetworkKind: String, CaseIterable, Identifiable {
    case client, broker, underwriter, department, surveyor, reinsurer

    /// Departments appear as group headers under underwriters, not as their own segment.
    static let segments: [NetworkKind] = [.client, .broker, .underwriter, .surveyor, .reinsurer]

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var plural: String { "\(title)s" }

    var symbol: String {
        switch self {
        case .client: "person.crop.square.fill"
        case .broker: "briefcase.fill"
        case .underwriter: "signature"
        case .department: "building.2.fill"
        case .surveyor: "magnifyingglass"
        case .reinsurer: "building.columns.fill"
        }
    }

    var tint: Color {
        switch self {
        case .client: Theme.teal
        case .broker: Theme.amber
        case .underwriter, .department: Theme.sky
        case .surveyor: Theme.coral
        case .reinsurer: Theme.lavender
        }
    }
}

/// A record in the Network tab. `key` is nil when creating a new one.
struct NetworkRoute: Hashable, Identifiable {
    var kind: NetworkKind
    var key: Int?
    var id: Self { self }
}
