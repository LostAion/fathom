import Foundation
import Testing
@testable import Fathom

struct BridgeMetricsTests {
    private let today = APIDate.parse("2026-10-14")!

    private func policy(_ no: Int, _ type: PolicyType, insured: String, premium: String, status: PolicyStatus, expiry: String = "2027-10-14") -> Policy {
        Policy(policyNo: no, expiryDate: expiry, premium: premium, sumInsured: insured, policyType: type, status: status.rawValue)
    }

    private func claim(_ id: Int, policy: Int, amount: String, status: ClaimStatus, settled: String? = nil) -> Claim {
        Claim(claimId: id, claimAmount: amount, policyNo: policy, status: status.rawValue, settledAmount: settled)
    }

    @Test func totalsSkipCancelledPolicies() {
        let metrics = BridgeMetrics(
            policies: [policy(1, .hull, insured: "1000000", premium: "20000", status: .bound),
                       policy(2, .cargo, insured: "500000", premium: "5000", status: .cancelled)],
            claims: [], reinsuredBy: [], assessedBy: [], today: today)
        #expect(metrics.totalInsured == 1_000_000)
        #expect(metrics.premium == 20_000)
        #expect(metrics.rateOnLine == 0.02)
    }

    @Test func cededUsesSharePercentOfEachPolicy() {
        let metrics = BridgeMetrics(
            policies: [policy(1, .hull, insured: "1000000", premium: "1", status: .bound)],
            claims: [],
            reinsuredBy: [ReinsuredBy(policyNo: 1, reinsurerId: 1, sharePercent: "40.00"),
                          ReinsuredBy(policyNo: 1, reinsurerId: 2, sharePercent: "25.50")],
            assessedBy: [], today: today)
        #expect(metrics.ceded == 655_000)
        #expect(metrics.cededShare == 0.655)
    }

    @Test func incurredCountsPayoutsForSettledAndAmountsForOpenClaims() {
        let metrics = BridgeMetrics(
            policies: [policy(1, .hull, insured: "1000000", premium: "100000", status: .bound),
                       policy(2, .pi, insured: "1000000", premium: "100000", status: .bound)],
            claims: [claim(1, policy: 1, amount: "60000", status: .settled, settled: "50000"),
                     claim(2, policy: 1, amount: "30000", status: .reported),
                     claim(3, policy: 2, amount: "99999", status: .rejected)],
            reinsuredBy: [], assessedBy: [], today: today)
        #expect(metrics.incurred == 80_000)
        #expect(metrics.lossRatio == 0.4)
        #expect(metrics.byType.map(\.type) == [.hull, .cargo, .pi])
        #expect(metrics.byType[0].lossRatio == 0.8)
        #expect(metrics.byType[1].lossRatio == nil)
        #expect(metrics.byType[2].incurred == 0)
    }

    @Test func activeCountsAsBoundStage() {
        let metrics = BridgeMetrics(
            policies: [policy(1, .hull, insured: "10", premium: "1", status: .active),
                       policy(2, .hull, insured: "20", premium: "1", status: .bound),
                       policy(3, .hull, insured: "5", premium: "1", status: .draft)],
            claims: [], reinsuredBy: [], assessedBy: [], today: today)
        #expect(metrics.byStage.map(\.stage) == [.draft, .quoted, .bound])
        #expect(metrics.byStage.map(\.count) == [1, 0, 2])
        #expect(metrics.byStage[2].sumInsured == 30)
    }

    @Test func expiringBucketsAndPastPolicies() {
        let metrics = BridgeMetrics(
            policies: [policy(1, .hull, insured: "1", premium: "1", status: .bound, expiry: "2026-10-14"),
                       policy(2, .hull, insured: "1", premium: "1", status: .bound, expiry: "2026-11-13"),
                       policy(3, .hull, insured: "1", premium: "1", status: .bound, expiry: "2026-11-14"),
                       policy(4, .hull, insured: "1", premium: "1", status: .bound, expiry: "2027-01-12"),
                       policy(5, .hull, insured: "1", premium: "1", status: .bound, expiry: "2026-10-01")],
            claims: [], reinsuredBy: [], assessedBy: [], today: today)
        #expect(metrics.expiring == [2, 1, 1])
    }

    @Test func attentionListsWorkToDo() {
        let metrics = BridgeMetrics(
            policies: [policy(1, .hull, insured: "1", premium: "1", status: .draft),
                       policy(2, .hull, insured: "1", premium: "1", status: .quoted),
                       policy(3, .hull, insured: "1", premium: "1", status: .bound, expiry: "2026-10-20"),
                       policy(4, .hull, insured: "1", premium: "1", status: .bound)],
            claims: [claim(1, policy: 4, amount: "5", status: .reported),
                     claim(2, policy: 4, amount: "5", status: .reported)],
            reinsuredBy: [ReinsuredBy(policyNo: 4, reinsurerId: 1, sharePercent: "50")],
            assessedBy: [AssessedBy(claimId: 2, surveyorId: 1)],
            today: today)
        let kinds = metrics.attention.map(\.kind)
        #expect(kinds == [.quote, .bind, .unplaced, .expiring, .survey])
        #expect(metrics.attention[3].detail == "Expires in 6 days")
        #expect(metrics.attention[4].route == .claim(1))
    }
}
