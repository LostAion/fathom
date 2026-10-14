import Foundation
import Testing
@testable import Fathom

struct ClaimsMathTests {
    private func policy(no: Int = 1, sumInsured: String = "500000", deductible: String = "10000",
                        status: String = "BOUND") -> Policy {
        Policy(policyNo: no, issueDate: "2026-01-01", expiryDate: "2026-12-31", sumInsured: sumInsured,
               status: status, deductible: deductible)
    }

    private func claim(_ id: Int, policy: Int = 1, amount: String = "0", status: ClaimStatus,
                       settled: String? = nil, lossDate: String? = nil) -> Claim {
        Claim(claimId: id, lossDate: lossDate, claimAmount: amount, policyNo: policy,
              status: status.rawValue, settledAmount: settled)
    }

    // MARK: - Payout (mirrors POST claims/{id}/settle)

    @Test func payoutSubtractsDeductible() {
        let estimate = PayoutEstimate(claimAmount: 60_000, claimId: 0, policy: policy(), claims: [])
        #expect(estimate.payout == 50_000)
        #expect(estimate.deductibleCut == 10_000)
        #expect(estimate.limitCut == 0)
    }

    @Test func payoutNeverGoesBelowZero() {
        let estimate = PayoutEstimate(claimAmount: 4_000, claimId: 0, policy: policy(), claims: [])
        #expect(estimate.payout == 0)
        #expect(estimate.afterDeductible == 0)
        #expect(estimate.deductibleCut == 4_000)
    }

    @Test func payoutIsCappedByOtherSettledClaimsOnTheSamePolicy() {
        let claims = [
            claim(1, status: .settled, settled: "420000"),
            claim(2, status: .settled, settled: "50000"),
            // Not counted: open, rejected, another policy, and the claim itself.
            claim(3, amount: "999999", status: .underSurvey),
            claim(4, status: .rejected, settled: "100000"),
            claim(5, policy: 2, status: .settled, settled: "300000"),
            claim(9, status: .settled, settled: "77777"),
        ]
        let estimate = PayoutEstimate(claimAmount: 60_000, claimId: 9, policy: policy(), claims: claims)
        #expect(estimate.otherSettled == 470_000)
        #expect(estimate.remainingLimit == 30_000)
        #expect(estimate.payout == 30_000)
        #expect(estimate.limitCut == 20_000)
    }

    @Test func exhaustedLimitPaysNothing() {
        let claims = [claim(1, status: .settled, settled: "600000")]
        let estimate = PayoutEstimate(claimAmount: 60_000, claimId: 0, policy: policy(), claims: claims)
        #expect(estimate.remainingLimit == 0)
        #expect(estimate.payout == 0)
    }

    @Test func decimalAmountsStayExact() {
        let estimate = PayoutEstimate(claimAmount: Decimal(string: "10000.01")!, claimId: 0,
                                      policy: policy(deductible: "10000.00"), claims: [])
        #expect(estimate.payout == Decimal(string: "0.01"))
    }

    // MARK: - Coverage period

    @Test(arguments: ["2026-01-01", "2026-06-15", "2026-12-31"])
    func lossInsideCoverIsAccepted(day: String) {
        #expect(CoverageCheck(lossDay: day, issueDay: "2026-01-01", expiryDay: "2026-12-31") == .covered)
    }

    @Test func lossBeforeOrAfterCoverIsRejectedWithReason() {
        let early = CoverageCheck(lossDay: "2025-12-31", issueDay: "2026-01-01", expiryDay: "2026-12-31")
        #expect(early == .beforeStart("2026-01-01"))
        #expect(early.explanation?.contains("starts") == true)

        let late = CoverageCheck(lossDay: "2027-01-01", issueDay: "2026-01-01", expiryDay: "2026-12-31")
        #expect(late == .afterEnd("2026-12-31"))
        #expect(late.explanation?.contains("ended") == true)
    }

    @Test func missingCoverDatesLeaveThatSideOpen() {
        #expect(CoverageCheck(lossDay: "1990-01-01", issueDay: nil, expiryDay: "2026-12-31").isCovered)
        #expect(!CoverageCheck(lossDay: "2030-01-01", issueDay: nil, expiryDay: "2026-12-31").isCovered)
    }

    @Test func todayUsesTheLocalCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        // 23:43 UTC on 13 Oct is already 14 Oct in India.
        let now = Date(timeIntervalSince1970: 1_791_935_000)
        #expect(APIDate.today(calendar: calendar, now: now) == "2026-10-14")
    }

    // MARK: - Status

    @Test func statusStepsFollowTheTimeline() {
        #expect(ClaimStatus.reported.step < ClaimStatus.underSurvey.step)
        #expect(ClaimStatus.underSurvey.step < ClaimStatus.settled.step)
        #expect(ClaimStatus.settled.step == ClaimStatus.rejected.step)
        #expect(ClaimStatus.allCases.filter(\.isOpen) == [.reported, .underSurvey])
    }

    @Test func onlyBoundOrActivePoliciesTakeClaims() {
        let takes = PolicyStatus.allCases.filter { policy(status: $0.rawValue).canTakeClaims }
        #expect(takes == [.bound, .active])
    }

    @Test func boardSummaryAddsOpenExposureAndPayouts() {
        let summary = ClaimBoardSummary(claims: [
            claim(1, amount: "185000", status: .reported),
            claim(2, amount: "450000", status: .underSurvey),
            claim(3, amount: "60000", status: .settled, settled: "50000"),
            claim(4, amount: "70000", status: .rejected),
        ])
        #expect(summary.openExposure == 635_000)
        #expect(summary.settledTotal == 50_000)
        #expect(summary.counts == [.reported: 1, .underSurvey: 1, .settled: 1, .rejected: 1])
    }

    @Test func boardSortsNewestLossFirst() {
        let sorted = ClaimSorting.newestFirst([
            claim(1, status: .reported, lossDate: "2026-05-14"),
            claim(2, status: .reported, lossDate: nil),
            claim(3, status: .reported, lossDate: "2026-07-22"),
            claim(4, status: .reported, lossDate: "2026-07-22"),
        ])
        #expect(sorted.map(\.claimId) == [4, 3, 1, 2])
    }
}
