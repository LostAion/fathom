import Foundation

/// Dashboard numbers. The API has no aggregate endpoints, so these are computed
/// from the full tables in the ledger.
nonisolated struct BridgeMetrics {
    struct TypeSlice: Identifiable {
        let type: PolicyType
        let count: Int
        let premium: Decimal
        let incurred: Decimal
        var id: PolicyType { type }
        /// Incurred losses over premium, nil when there is no premium.
        var lossRatio: Double? { premium > 0 ? (incurred / premium).double : nil }
    }

    struct StageSlice: Identifiable {
        let stage: PolicyStatus
        let count: Int
        let sumInsured: Decimal
        var id: PolicyStatus { stage }
    }

    struct Attention: Identifiable {
        enum Kind { case quote, bind, survey, expiring, unplaced }
        let kind: Kind
        let title: String
        let detail: String
        let route: AppRoute
        var id: String { "\(kind)-\(title)" }
    }

    /// Policies that are not cancelled.
    let live: [Policy]
    let totalInsured: Decimal
    let premium: Decimal
    /// Sum insured passed on to reinsurers (share % of each policy).
    let ceded: Decimal
    /// Settled payouts plus open claim amounts. Rejected claims don't count.
    let incurred: Decimal
    let byType: [TypeSlice]
    let byStage: [StageSlice]
    /// Live policies expiring within 0-30, 31-60 and 61-90 days.
    let expiring: [Int]
    let attention: [Attention]

    var lossRatio: Double? { premium > 0 ? (incurred / premium).double : nil }
    var rateOnLine: Double? { totalInsured > 0 ? (premium / totalInsured).double : nil }
    var cededShare: Double? { totalInsured > 0 ? (ceded / totalInsured).double : nil }

    init(policies: [Policy], claims: [Claim], reinsuredBy: [ReinsuredBy], assessedBy: [AssessedBy], today: Date = .now) {
        let live = policies.filter { $0.lifecycle != .cancelled }
        self.live = live
        totalInsured = live.compactMap(\.sumInsuredAmount).reduce(0, +)
        premium = live.compactMap(\.premiumAmount).reduce(0, +)

        let insuredByPolicy = Dictionary(uniqueKeysWithValues: live.map { ($0.policyNo, $0.sumInsuredAmount ?? 0) })
        ceded = reinsuredBy.reduce(0) { total, share in
            total + (insuredByPolicy[share.policyNo] ?? 0) * (share.share ?? 0) / 100
        }

        let livePolicyNos = Set(live.map(\.policyNo))
        let liveClaims = claims.filter { $0.policyNo.map(livePolicyNos.contains) ?? false && $0.state != .rejected }
        func incurredAmount(_ claim: Claim) -> Decimal {
            claim.state == .settled ? (claim.settledAmountValue ?? 0) : (claim.claimAmountValue ?? 0)
        }
        incurred = liveClaims.map(incurredAmount).reduce(0, +)

        let typeOf = Dictionary(uniqueKeysWithValues: live.map { ($0.policyNo, $0.policyType) })
        byType = PolicyType.allCases.map { type in
            let policies = live.filter { $0.policyType == type }
            return TypeSlice(
                type: type,
                count: policies.count,
                premium: policies.compactMap(\.premiumAmount).reduce(0, +),
                incurred: liveClaims.filter { typeOf[$0.policyNo ?? -1] == type }.map(incurredAmount).reduce(0, +)
            )
        }

        byStage = [PolicyStatus.draft, .quoted, .bound].map { stage in
            // ACTIVE is in force too, so it counts with BOUND.
            let policies = live.filter { stage == .bound ? [.bound, .active].contains($0.lifecycle) : $0.lifecycle == stage }
            return StageSlice(stage: stage, count: policies.count, sumInsured: policies.compactMap(\.sumInsuredAmount).reduce(0, +))
        }

        let daysLeft = Dictionary(uniqueKeysWithValues: live.compactMap { policy in
            policy.expires.map { (policy.policyNo, Self.days(from: today, to: $0)) }
        })
        expiring = [0...30, 31...60, 61...90].map { range in daysLeft.values.count { range.contains($0) } }

        var items: [Attention] = []
        for policy in live.sorted(by: { $0.policyNo < $1.policyNo }) {
            let name = "Policy #\(policy.policyNo)"
            switch policy.lifecycle {
            case .draft:
                items.append(Attention(kind: .quote, title: name, detail: "Draft waiting for a quote", route: .policy(policy.policyNo)))
            case .quoted:
                items.append(Attention(kind: .bind, title: name, detail: "Quoted, not yet bound", route: .policy(policy.policyNo)))
            case .bound, .active:
                if !reinsuredBy.contains(where: { $0.policyNo == policy.policyNo }) {
                    items.append(Attention(kind: .unplaced, title: name, detail: "Bound with no reinsurance placed", route: .policy(policy.policyNo)))
                }
            default:
                break
            }
            if let days = daysLeft[policy.policyNo], (0...30).contains(days) {
                items.append(Attention(kind: .expiring, title: name, detail: days == 0 ? "Expires today" : "Expires in \(counted(days, "day"))", route: .policy(policy.policyNo)))
            }
        }
        let surveyed = Set(assessedBy.map(\.claimId))
        for claim in liveClaims where claim.state == .reported && !surveyed.contains(claim.claimId) {
            items.append(Attention(kind: .survey, title: "Claim #\(claim.claimId)", detail: "Reported, no surveyor assigned", route: .claim(claim.claimId)))
        }
        attention = items
    }

    /// Whole days between two dates, counted on the UTC calendar the API dates use.
    static func days(from start: Date, to end: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}

extension Decimal {
    nonisolated var double: Double { NSDecimalNumber(decimal: self).doubleValue }
}
