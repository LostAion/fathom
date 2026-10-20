import SwiftUI

/// Everything a policy points at or is pointed at by, joined from the ledger.
struct PolicyLinks {
    let policy: Policy
    let client: Client?
    let broker: Broker?
    let underwriter: Underwriter?
    let vessel: Vessel?
    let cargo: Cargo?
    let claims: [Claim]
    let shares: [ReinsuredBy]
    let reinsurers: [Int: Reinsurer]

    init(_ policy: Policy, in ledger: Ledger) {
        self.policy = policy
        client = ledger.clients.first { $0.id == policy.clientId }
        broker = ledger.brokers.first { $0.id == policy.brokerId }
        underwriter = ledger.underwriters.first { $0.id == policy.empId }
        vessel = ledger.vessels.first { $0.id == policy.vesselId }
        cargo = ledger.cargos.first { $0.id == policy.cargoId }
        claims = ledger.claims.filter { $0.policyNo == policy.policyNo }.sorted { ($0.lost ?? .distantPast) < ($1.lost ?? .distantPast) }
        shares = ledger.reinsuredBy.filter { $0.policyNo == policy.policyNo }.sorted { $0.reinsurerId < $1.reinsurerId }
        reinsurers = Dictionary(uniqueKeysWithValues: ledger.reinsurers.map { ($0.id, $0) })
    }

    var placedPercent: Decimal { shares.compactMap(\.share).reduce(0, +) }
}

/// Wallet filter chips.
enum PolicyFilter: String, CaseIterable, Identifiable {
    case all, hull, cargo, pi, expiring, draft, quoted, bound

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .hull: "Hull"
        case .cargo: "Cargo"
        case .pi: "P&I"
        case .expiring: "Expiring"
        case .draft: "Draft"
        case .quoted: "Quoted"
        case .bound: "Bound"
        }
    }

    var symbol: String {
        switch self {
        case .all: "rectangle.stack.fill"
        case .hull: PolicyType.hull.symbol
        case .cargo: PolicyType.cargo.symbol
        case .pi: PolicyType.pi.symbol
        case .expiring: "hourglass"
        case .draft: "pencil.and.scribble"
        case .quoted: "doc.text.fill"
        case .bound: "seal.fill"
        }
    }

    var tint: Color {
        switch self {
        case .all: Theme.teal
        case .hull: PolicyType.hull.tint
        case .cargo: PolicyType.cargo.tint
        case .pi: PolicyType.pi.tint
        case .expiring: Theme.amber
        case .draft: PolicyStatus.draft.tint
        case .quoted: PolicyStatus.quoted.tint
        case .bound: PolicyStatus.bound.tint
        }
    }

    func matches(_ policy: Policy, today: Date) -> Bool {
        switch self {
        case .all: true
        case .hull: policy.policyType == .hull
        case .cargo: policy.policyType == .cargo
        case .pi: policy.policyType == .pi
        case .expiring:
            policy.lifecycle != .cancelled && PolicyMath.expiry(of: policy.expires, today: today).isExpiringSoon
        case .draft: policy.stage == .draft
        case .quoted: policy.stage == .quoted
        case .bound: policy.stage == .bound || policy.stage == .active
        }
    }
}

extension Policy {
    /// Lifecycle with a missing status read as a draft, which is the server default.
    var stage: PolicyStatus { lifecycle ?? .draft }

    var numberTitle: String { "Policy #\(policyNo)" }

    /// The column that only applies to this policy's type.
    var typeSpecific: (label: String, value: String?)? {
        switch policyType {
        case .hull: ("Vessel value covered", Decimal(apiString: vesselValueCovered)?.money)
        case .cargo: ("Cargo type", cargoType)
        case .pi: ("Liability limit", Decimal(apiString: liabilityLimit)?.money)
        case nil: nil
        }
    }
}

enum PolicyFormat {
    /// "0.09%", "2.5%", "12.125%".
    static func percent(_ value: Decimal) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...3))))%"
    }

    /// Dates are stored as midnight GMT, so show them in GMT to keep the right day.
    static func day(_ date: Date?) -> String {
        date?.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt)) ?? "Not set"
    }

    static func stage(_ status: PolicyStatus) -> String { status.rawValue.capitalized }
}

/// Shades for reinsurers in the donut and the share bar, with "Retained" kept neutral.
enum ShareColors {
    static let retained = Theme.inkMuted.opacity(0.22)

    static func reinsurer(_ index: Int) -> Color {
        [Theme.lavender, Theme.sky, Theme.lavender.opacity(0.6), Theme.sky.opacity(0.6)][index % 4]
    }
}
