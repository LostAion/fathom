import Foundation

/// What `POST claims/{id}/settle` will pay, worked out the same way as the server:
/// min(max(0, claim − deductible), max(0, sum insured − other settled payouts on the policy)).
nonisolated struct PayoutEstimate: Equatable {
    var claimAmount: Decimal
    var deductible: Decimal
    var sumInsured: Decimal
    /// Payouts already made on other SETTLED claims under the same policy.
    var otherSettled: Decimal

    var afterDeductible: Decimal { max(0, claimAmount - deductible) }
    /// What is left of the policy's aggregate limit.
    var remainingLimit: Decimal { max(0, sumInsured - otherSettled) }
    var payout: Decimal { min(afterDeductible, remainingLimit) }
    /// The part of the claim the deductible removes.
    var deductibleCut: Decimal { claimAmount - afterDeductible }
    /// The part removed because the aggregate limit is used up.
    var limitCut: Decimal { afterDeductible - payout }
}

nonisolated extension PayoutEstimate {
    /// `claim` may be a claim that is not saved yet (id 0); it is never counted as "other".
    init(claimAmount: Decimal, claimId: Int, policy: Policy?, claims: [Claim]) {
        let others = claims.filter {
            $0.policyNo == policy?.policyNo && $0.claimId != claimId && $0.state == .settled
        }
        self.init(
            claimAmount: claimAmount,
            deductible: policy?.deductibleAmount ?? 0,
            sumInsured: policy?.sumInsuredAmount ?? 0,
            otherSettled: others.compactMap(\.settledAmountValue).reduce(0, +)
        )
    }
}

/// Whether a loss date falls inside the policy's coverage period (both ends included).
/// Days are compared as "yyyy-MM-dd" strings, so time zones can't shift them.
nonisolated enum CoverageCheck: Equatable {
    case covered
    case beforeStart(String)
    case afterEnd(String)

    init(lossDay: String, issueDay: String?, expiryDay: String?) {
        if let issueDay, lossDay < issueDay {
            self = .beforeStart(issueDay)
        } else if let expiryDay, lossDay > expiryDay {
            self = .afterEnd(expiryDay)
        } else {
            self = .covered
        }
    }

    var isCovered: Bool { self == .covered }

    var explanation: String? {
        switch self {
        case .covered: nil
        case .beforeStart(let day): "Cover starts on \(APIDate.parse(day)?.dayText ?? day). Losses before that aren't insured."
        case .afterEnd(let day): "Cover ended on \(APIDate.parse(day)?.dayText ?? day). Losses after that aren't insured."
        }
    }
}

nonisolated extension ClaimStatus {
    /// Position on the Reported → Under survey → Settled / Rejected timeline.
    var step: Int {
        switch self {
        case .reported: 0
        case .underSurvey: 1
        case .settled, .rejected: 2
        }
    }

    /// Settled and rejected claims are closed and read-only.
    var isOpen: Bool { step < 2 }
}

nonisolated extension Policy {
    /// Only bound or active cover can take claims.
    var canTakeClaims: Bool { lifecycle == .bound || lifecycle == .active }
}

/// Headline numbers for the incident board.
nonisolated struct ClaimBoardSummary: Equatable {
    /// Claimed amounts still waiting on a decision (reported or under survey).
    var openExposure: Decimal = 0
    var settledTotal: Decimal = 0
    var counts: [ClaimStatus: Int] = [:]

    init(claims: [Claim]) {
        for claim in claims {
            guard let state = claim.state else { continue }
            counts[state, default: 0] += 1
            if state.isOpen { openExposure += claim.claimAmountValue ?? 0 }
            if state == .settled { settledTotal += claim.settledAmountValue ?? 0 }
        }
    }
}

nonisolated enum ClaimSorting {
    /// Newest loss first; claims without a loss date go last, ties by newest id.
    static func newestFirst(_ claims: [Claim]) -> [Claim] {
        claims.sorted { a, b in
            switch (a.lossDate, b.lossDate) {
            case let (x?, y?) where x != y: x > y
            case (nil, _?): false
            case (_?, nil): true
            default: a.claimId > b.claimId
            }
        }
    }
}

// MARK: - Days

nonisolated extension Date {
    /// "14 May 2026". API dates are midnight GMT, so format them in GMT too.
    var dayText: String {
        formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))
    }
}

nonisolated extension APIDate {
    /// Today's date on the user's calendar, as an API day string.
    static func today(calendar: Calendar = .current, now: Date = .now) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
