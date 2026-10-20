import SwiftUI

/// Runs the backend's concurrency demos and replays both threads on a timeline,
/// showing why the unlocked run breaks the policy limit and the locked run doesn't.
struct ConcurrencyLabView: View {
    @Environment(Ledger.self) private var ledger
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scenario = ConcurrencyScenario.unsafe
    @State private var run: ConcurrencyRun?
    @State private var running = false
    @State private var progress = 0.0
    @State private var error: String?
    @State private var cleaning = false

    private static let demoClient = "Concurrency Demo Shipper"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Concurrency Lab")
                        .font(.rounded(.largeTitle, weight: .bold))
                    Text("Two adjusters settle $60,000 claims on the same $100,000 policy at the same moment. Pick how the database handles it.")
                        .foregroundStyle(Theme.inkMuted)
                }

                scenarioPicker
                runButton

                if let error {
                    GlassCard(tint: Theme.coral) {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                    }
                }

                if let run {
                    timeline(run)
                    outcome(run)
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "What happened")
                            Text(run.explanation)
                                .font(.callout)
                        }
                    }
                    log(run)
                }

                cleanup
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .foregroundStyle(Theme.ink)
        .background { SonarBackground() }
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(trigger: run?.policyNo) { _, _ in
            guard let run else { return nil }
            return run.limitHeld ? .success : .error
        }
    }

    // MARK: - Controls

    private var scenarioPicker: some View {
        HStack(spacing: 12) {
            ForEach(ConcurrencyScenario.allCases) { option in
                let selected = option == scenario
                Button {
                    withAnimation(.snappy) {
                        scenario = option
                        run = nil
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(option.title, systemImage: option == .unsafe ? "lock.open.fill" : "lock.fill")
                            .font(.rounded(.headline))
                            .foregroundStyle(selected ? (option == .unsafe ? Theme.coral : Theme.teal) : Theme.ink)
                        Text(option.summary)
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(14)
                }
                .buttonStyle(.plain)
                .glassEffect(selected ? .regular.tint((option == .unsafe ? Theme.coral : Theme.teal).opacity(0.2)).interactive() : .regular.interactive(),
                             in: .rect(cornerRadius: 20))
                .accessibilityLabel(option.title)
                .accessibilityHint(option.summary)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var runButton: some View {
        Button {
            Task { await start() }
        } label: {
            HStack {
                if running { ProgressView() }
                Text(running ? "Running on MariaDB…" : run == nil ? "Run on MariaDB" : "Run again")
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(scenario == .unsafe ? Theme.coral : Theme.teal)
        .controlSize(.large)
        .font(.rounded(.headline))
        .disabled(running)
    }

    // MARK: - Results

    private func timeline(_ run: ConcurrencyRun) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: "Timeline")
                    Spacer()
                    Button("Replay", systemImage: "arrow.counterclockwise") { replay() }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.glass)
                }
                ThreadLanes(events: run.events, progress: progress)
                LaneLegend()
            }
        }
    }

    private func outcome(_ run: ConcurrencyRun) -> some View {
        let paid = run.totalClaimsPaid
        let limit = run.policyAggregateLimit
        let verdict = run.limitHeld
            ? "Limit held: \(paid.dollars) paid, the second claim was rolled back."
            : "Limit broken: \(paid.dollars) paid on a \(limit.dollars) limit."
        return GlassCard(tint: run.limitHeld ? Theme.teal : Theme.coral) {
            VStack(alignment: .leading, spacing: 12) {
                Label(run.limitHeld ? "Consistent" : "Lost update", systemImage: run.limitHeld ? "checkmark.shield.fill" : "xmark.octagon.fill")
                    .font(.rounded(.title3, weight: .bold))
                    .foregroundStyle(run.limitHeld ? Theme.teal : Theme.coral)
                Text(verdict)
                    .font(.callout)
                LimitBar(results: run.threadResults, limit: limit)
                    .accessibilityElement()
                    .accessibilityLabel(verdict)
            }
        }
    }

    private func log(_ run: ConcurrencyRun) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Execution log", count: run.events.count)
                ForEach(run.events) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(String(format: "%.3fs", event.time))
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.inkMuted)
                        Text("T\(event.thread)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ThreadLanes.color(for: event.thread))
                        Text(event.text)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private var cleanup: some View {
        let client = ledger.clients.first { $0.name == Self.demoClient }
        let policies = ledger.policies.filter { client != nil && $0.clientId == client?.id }
        if let client {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Each run creates a demo policy and claims for \"\(Self.demoClient)\". \(counted(policies.count, "demo policy", "demo policies")) on file.")
                        .font(.callout)
                        .foregroundStyle(Theme.inkMuted)
                    Button(cleaning ? "Removing…" : "Remove demo records", systemImage: "trash") {
                        Task { await removeDemoRecords(client: client, policies: policies) }
                    }
                    .buttonStyle(.glass)
                    .disabled(cleaning || running)
                }
            }
        }
    }

    // MARK: - Actions

    private func start() async {
        running = true
        error = nil
        defer { running = false }
        do {
            let result: ConcurrencyRun = try await APIClient.shared.action(scenario.path)
            progress = 0
            withAnimation(.snappy) { run = result }
            replay()
            await ledger.refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func replay() {
        progress = 0
        if reduceMotion {
            progress = 1
        } else {
            withAnimation(.linear(duration: 2.5)) { progress = 1 }
        }
    }

    /// Deleting the policies cascades to their claims; then the client goes.
    private func removeDemoRecords(client: Client, policies: [Policy]) async {
        cleaning = true
        defer { cleaning = false }
        do {
            for policy in policies {
                try await APIClient.shared.delete(policy)
            }
            try await APIClient.shared.delete(client)
            withAnimation { run = nil }
            await ledger.refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Timeline

/// One lane per thread on a shared time axis. `progress` (0...1) reveals events as time passes.
private struct ThreadLanes: View, Animatable {
    let events: [LabEvent]
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    static func color(for thread: Int) -> Color { thread == 1 ? Theme.sky : Theme.rose }

    private var threads: [Int] { Array(Set(events.map(\.thread))).sorted() }
    private var duration: Double { max(events.map(\.time).max() ?? 0, 0.01) * 1.08 }
    private var now: Double { progress * duration }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(threads, id: \.self) { thread in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle().fill(Self.color(for: thread)).frame(width: 8, height: 8)
                        Text("Adjuster \(thread == 1 ? "A" : "B") · Thread \(thread)")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
                    lane(thread)
                        .frame(height: 22)
                }
                .accessibilityElement()
                .accessibilityLabel(laneSummary(thread))
            }
            axis
        }
    }

    private func lane(_ thread: Int) -> some View {
        let mine = events.filter { $0.thread == thread }
        let requested = mine.first { $0.kind == .lockRequested }?.time
        let acquired = mine.first { $0.kind == .lockAcquired }?.time
        let start = acquired ?? mine.first?.time ?? 0
        let end = mine.last { $0.kind == .commit || $0.kind == .rollback }?.time ?? mine.last?.time ?? start
        let color = Self.color(for: thread)

        return GeometryReader { geo in
            let x = { (t: Double) in geo.size.width * min(t, now) / duration }
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.inkMuted.opacity(0.15))
                    .frame(height: 4)
                if let requested, let acquired, now > requested {
                    Capsule()
                        .fill(Theme.amber.opacity(0.55))
                        .frame(width: max(x(acquired) - x(requested), 2), height: 10)
                        .offset(x: x(requested))
                }
                if now > start {
                    Capsule()
                        .fill(color)
                        .frame(width: max(x(end) - x(start), 2), height: 10)
                        .offset(x: x(start))
                }
                ForEach(mine.filter { $0.time <= now }) { event in
                    Circle()
                        .fill(dotColor(event, lane: color))
                        .overlay(Circle().stroke(Theme.abyss, lineWidth: 2))
                        .frame(width: 12, height: 12)
                        .offset(x: x(event.time) - 6)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var axis: some View {
        HStack {
            Text("0s")
            Spacer()
            Text(String(format: "%.2fs", duration / 2))
            Spacer()
            Text(String(format: "%.2fs", duration))
        }
        .font(.caption2.monospaced())
        .foregroundStyle(Theme.inkMuted)
        .accessibilityHidden(true)
    }

    private func dotColor(_ event: LabEvent, lane: Color) -> Color {
        switch event.kind {
        case .commit: Theme.teal
        case .rollback: Theme.coral
        case .lockRequested: Theme.amber
        default: lane
        }
    }

    private func laneSummary(_ thread: Int) -> String {
        let steps = events.filter { $0.thread == thread }.map { String(format: "%.3f seconds, %@", $0.time, $0.text) }
        return "Thread \(thread): " + steps.joined(separator: ". ")
    }
}

private struct LaneLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            item("Waiting for lock", Theme.amber)
            item("Commit", Theme.teal)
            item("Rollback", Theme.coral)
        }
        .font(.caption2)
        .foregroundStyle(Theme.inkMuted)
        .accessibilityHidden(true)
    }

    private func item(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}

/// Approved payouts stacked against the aggregate limit; anything past the limit is drawn in coral.
private struct LimitBar: View {
    let results: [ConcurrencyRun.ThreadResult]
    let limit: Double

    private var approved: [(thread: Int, amount: Double)] {
        results.compactMap { result in
            guard result.status == "APPROVED", let amount = result.amount else { return nil }
            return (Int(result.thread.filter(\.isNumber)) ?? 0, amount)
        }
    }

    var body: some View {
        let paid = approved.map(\.amount).reduce(0, +)
        let scale = max(limit, paid) * 1.1
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.inkMuted.opacity(0.12))
                    HStack(spacing: 2) {
                        ForEach(approved, id: \.thread) { item in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(ThreadLanes.color(for: item.thread))
                                .frame(width: w * item.amount / scale)
                        }
                    }
                    if paid > limit {
                        Rectangle()
                            .fill(Theme.coral.opacity(0.45))
                            .frame(width: w * (paid - limit) / scale)
                            .offset(x: w * limit / scale)
                    }
                    Rectangle()
                        .fill(Theme.ink)
                        .frame(width: 2)
                        .offset(x: w * limit / scale - 1)
                }
            }
            .frame(height: 28)
            HStack {
                Text("Paid \(paid.dollars)")
                Spacer()
                Text("Limit \(limit.dollars)")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.inkMuted)
        }
    }
}

private extension Double {
    var dollars: String { formatted(.currency(code: "USD").precision(.fractionLength(0))) }
}
