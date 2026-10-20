import Foundation
import Testing
@testable import Fathom

struct ConcurrencyRunTests {
    @Test func parsesLogLines() throws {
        let event = try #require(LabEvent(logLine: "[Thread-2 @ 0.241s] ACQUIRED row lock on Policy #7 (Waited 0.163s in lock queue)"))
        #expect(event.thread == 2)
        #expect(event.time == 0.241)
        #expect(event.kind == .lockAcquired)
        #expect(LabEvent(logLine: "garbage") == nil)
    }

    @Test(arguments: [
        ("Requesting exclusive lock: SELECT ... FOR UPDATE", LabEvent.Kind.lockRequested),
        ("Non-locking read: Remaining aggregate capacity = $100,000.00", .read),
        ("Verified remaining aggregate limit: $40,000.00", .read),
        ("COMMITTED $60,000.00 payout based on stale read.", .commit),
        ("Exceeds aggregate limit ($60k > $40,000.00) -> Submitting ROLLBACK...", .rollback),
        ("Transaction rolled back. Lock released.", .rollback),
    ])
    func classifiesEvents(text: String, kind: LabEvent.Kind) throws {
        #expect(try #require(LabEvent(logLine: "[Thread-1 @ 0.010s] \(text)")).kind == kind)
    }

    @Test func decodesServerResponse() throws {
        let json = """
        {"scenario":"PESSIMISTIC_LOCK_SAFE","policy_no":9,"policy_aggregate_limit":100000.0,
         "thread_results":[{"thread":"Thread-1","status":"APPROVED","amount":60000.0},
                           {"thread":"Thread-2","status":"REJECTED_CONCURRENCY_LIMIT","reason":"x"}],
         "total_claims_paid":60000.0,"invariant_preserved":true,"academic_mechanism":"InnoDB row lock",
         "execution_log":["[Thread-2 @ 0.300s] Transaction rolled back. Lock released.",
                          "[Thread-1 @ 0.001s] Requesting exclusive lock: SELECT ... FOR UPDATE"]}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let run = try decoder.decode(ConcurrencyRun.self, from: Data(json.utf8))
        #expect(run.limitHeld)
        #expect(run.explanation == "InnoDB row lock")
        #expect(run.events.map(\.thread) == [1, 2])
    }
}
