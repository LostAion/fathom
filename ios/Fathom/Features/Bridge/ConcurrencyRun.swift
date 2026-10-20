import Foundation

/// The two backend demos of concurrent claim settlement against one policy's aggregate limit.
nonisolated enum ConcurrencyScenario: String, CaseIterable, Identifiable {
    case unsafe = "demo-race-condition"
    case locked = "demo-safe-transaction"

    var id: Self { self }
    var path: String { "concurrency/\(rawValue)" }

    var title: String {
        switch self {
        case .unsafe: "Without locking"
        case .locked: "With row lock"
        }
    }

    var summary: String {
        switch self {
        case .unsafe: "Both adjusters read the remaining limit at the same time, then both pay out."
        case .locked: "SELECT ... FOR UPDATE makes the second adjuster wait until the first commits."
        }
    }
}

/// Response of `POST /api/concurrency/...`.
nonisolated struct ConcurrencyRun: Decodable {
    struct ThreadResult: Decodable, Hashable {
        var thread: String
        var status: String
        var amount: Double?
        var reason: String?
    }

    var scenario: String
    var policyNo: Int
    var policyAggregateLimit: Double
    var threadResults: [ThreadResult]
    var totalClaimsPaid: Double
    var invariantViolated: Bool?
    var invariantPreserved: Bool?
    var academicRootCause: String?
    var academicMechanism: String?
    var executionLog: [String]

    var limitHeld: Bool { invariantPreserved ?? !(invariantViolated ?? false) }
    var explanation: String { academicMechanism ?? academicRootCause ?? "" }
    var events: [LabEvent] { executionLog.compactMap(LabEvent.init(logLine:)).sorted { $0.time < $1.time } }
}

/// One line of the execution log, e.g. `[Thread-2 @ 0.241s] ACQUIRED row lock on Policy #7`.
nonisolated struct LabEvent: Identifiable, Hashable {
    enum Kind { case lockRequested, lockAcquired, read, commit, rollback, info }

    let thread: Int
    let time: Double
    let text: String
    let kind: Kind
    var id: String { "\(thread)-\(time)-\(text)" }

    init?(logLine: String) {
        guard let match = logLine.firstMatch(of: /^\[Thread-(\d+) @ ([\d.]+)s\] (.+)$/),
              let thread = Int(match.1), let time = Double(match.2)
        else { return nil }
        self.thread = thread
        self.time = time
        text = String(match.3)
        kind = Self.kind(of: text)
    }

    private static func kind(of text: String) -> Kind {
        let lower = text.lowercased()
        if lower.contains("requesting") { return .lockRequested }
        if lower.contains("acquired") { return .lockAcquired }
        if lower.contains("rollback") || lower.contains("rolled back") { return .rollback }
        if lower.contains("commit") { return .commit }
        if lower.contains("read") || lower.contains("remaining") { return .read }
        return .info
    }
}
