import Foundation
import Testing
@testable import Fathom

struct PoliciesMathTests {
    private func day(_ string: String) -> Date { APIDate.parse(string)! }

    // MARK: - Rate on line

    @Test func rateOnLineIsPremiumOverSumInsured() {
        #expect(PolicyMath.rateOnLine(premium: 45_000, sumInsured: 50_000_000) == Decimal(string: "0.09"))
        #expect(PolicyMath.rateOnLine(premium: 12_500, sumInsured: 2_500_000) == Decimal(string: "0.5"))
    }

    @Test func rateOnLineNeedsAPositiveSumInsured() {
        #expect(PolicyMath.rateOnLine(premium: 100, sumInsured: 0) == nil)
        #expect(PolicyMath.rateOnLine(premium: nil, sumInsured: 100) == nil)
        #expect(PolicyMath.rateOnLine(premium: 100, sumInsured: nil) == nil)
    }

    // MARK: - Expiry

    @Test func expiryClassification() {
        let today = day("2026-10-14")
        #expect(PolicyMath.expiry(of: nil, today: today) == .unknown)
        #expect(PolicyMath.expiry(of: day("2026-10-10"), today: today) == .expired(daysAgo: 4))
        #expect(PolicyMath.expiry(of: day("2026-10-14"), today: today) == .expiring(days: 0))
        #expect(PolicyMath.expiry(of: day("2027-01-12"), today: today) == .expiring(days: 90))
        #expect(PolicyMath.expiry(of: day("2027-01-13"), today: today) == .running(days: 91))
    }

    @Test func onlyTheWindowCountsAsExpiringSoon() {
        #expect(ExpiryState.expiring(days: 30).isExpiringSoon)
        #expect(!ExpiryState.expired(daysAgo: 1).isExpiringSoon)
        #expect(!ExpiryState.running(days: 200).isExpiringSoon)
    }

    @Test func expiringFilterSkipsCancelledPolicies() {
        let today = day("2026-10-14")
        var policy = Policy(policyNo: 1, expiryDate: "2026-11-01", status: "BOUND")
        #expect(PolicyFilter.expiring.matches(policy, today: today))
        policy.status = "CANCELLED"
        #expect(!PolicyFilter.expiring.matches(policy, today: today))
    }

    @Test func boundFilterIncludesActive() {
        #expect(PolicyFilter.bound.matches(Policy(policyNo: 1, status: "ACTIVE"), today: .now))
        #expect(PolicyFilter.draft.matches(Policy(policyNo: 1, status: nil), today: .now))
    }

    @Test func coverageProgressIsClamped() {
        let issue = day("2026-01-01"), expiry = day("2026-12-31")
        #expect(PolicyMath.coverageProgress(issue: issue, expiry: expiry, today: day("2025-06-01")) == 0)
        #expect(PolicyMath.coverageProgress(issue: issue, expiry: expiry, today: day("2027-06-01")) == 1)
        let middle = PolicyMath.coverageProgress(issue: issue, expiry: expiry, today: day("2026-07-02"))!
        #expect(abs(middle - 0.5) < 0.01)
        #expect(PolicyMath.coverageProgress(issue: expiry, expiry: issue, today: issue) == nil)
    }

    // MARK: - Log scale

    @Test func logScaleRoundTrips() {
        let scale = LogScale(lower: 100_000, upper: 2_000_000_000)
        #expect(scale.value(at: 0) == 100_000)
        #expect(abs(scale.value(at: 1) - 2_000_000_000) < 1)
        #expect(abs(scale.position(of: scale.value(at: 0.37)) - 0.37) < 0.000_001)
        #expect(scale.position(of: 1) == 0)
        #expect(scale.position(of: 9e12) == 1)
    }

    @Test func roundingKeepsThreeSignificantFigures() {
        #expect(LogScale.round(12_345_678, digits: 3) == 12_300_000)
        #expect(LogScale.round(98_760, digits: 3) == 98_800)
        #expect(LogScale.round(0, digits: 3) == 0)
        #expect(LogScale.round(12_345_678, digits: 3).apiString == "12300000")
    }

    // MARK: - Share split

    @Test func initialSharesAreCappedAtOneHundred() {
        let split = ShareSplit([(reinsurerId: 1, percent: 70), (reinsurerId: 2, percent: 50)])
        #expect(split.shares == [70, 30])
        #expect(split.retained == 0)
    }

    @Test func addingTakesOnlyFromRetained() {
        var split = ShareSplit([(reinsurerId: 1, percent: 90)])
        split.add(2)
        #expect(split.shares == [90, 10])
        split.add(2)
        #expect(split.reinsurerIds == [1, 2])
        split.remove(1)
        #expect(split.reinsurerIds == [2])
        #expect(split.retained == 90)
    }

    @Test func settingAShareNeverPassesOneHundred() {
        var split = ShareSplit([(reinsurerId: 1, percent: 40), (reinsurerId: 2, percent: 35)])
        split.setShare(0, to: 99)
        #expect(split.shares == [65, 35])
        #expect(split.total == 100)
        split.setShare(1, to: -3)
        #expect(split.shares == [65, 0])
    }

    // MARK: - Diff

    @Test func diffPostsPutsAndDeletes() {
        let existing = [
            ReinsuredBy(policyNo: 7, reinsurerId: 1, sharePercent: "40.00"),
            ReinsuredBy(policyNo: 7, reinsurerId: 2, sharePercent: "35.00"),
            ReinsuredBy(policyNo: 9, reinsurerId: 1, sharePercent: "50.00"),
        ]
        var split = ShareSplit(existing.filter { $0.policyNo == 7 }.map { (reinsurerId: $0.reinsurerId, percent: ShareSplit.wholePercent($0.share)) })
        split.remove(2)
        split.setShare(0, to: 45)
        split.add(3, percent: 15)

        let changes = split.changes(policyNo: 7, existing: existing)
        #expect(changes.delete.map(\.reinsurerId) == [2])
        #expect(changes.update == [ReinsuredBy(policyNo: 7, reinsurerId: 1, sharePercent: "45")])
        #expect(changes.create == [ReinsuredBy(policyNo: 7, reinsurerId: 3, sharePercent: "15")])
    }

    @Test func untouchedFractionalSharesAreNotRewritten() {
        let existing = [ReinsuredBy(policyNo: 7, reinsurerId: 1, sharePercent: "33.33")]
        let split = ShareSplit([(reinsurerId: 1, percent: ShareSplit.wholePercent(existing[0].share))])
        #expect(split.changes(policyNo: 7, existing: existing).isEmpty)
    }
}
