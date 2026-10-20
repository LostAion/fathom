import SwiftUI

/// One claim: status timeline, surveyors, settlement, edit and delete.
struct ClaimDetailView: View {
    let claimId: Int

    @Environment(Ledger.self) private var ledger
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var confirmingReject = false
    @State private var busy = false
    @State private var errorText: String?
    @State private var addingSurveyor = false
    /// Surveyor ids before "New surveyor" opened, so the new one can be assigned on return.
    @State private var surveyorsBefore: Set<Int> = []
    @State private var assigns = 0
    @State private var settles = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let claim, let state = claim.state {
                    hero(claim, state: state)
                    GlassCard { ClaimTimeline(status: state) }
                    surveyors(open: state.isOpen)
                    settlement(claim, state: state)
                } else {
                    ContentUnavailableView("Claim removed", systemImage: "lifepreserver")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .animation(reduceMotion ? nil : .snappy, value: claim)
        }
        .foregroundStyle(Theme.ink)
        .background { SonarBackground() }
        .navigationTitle("Claim #\(claimId)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let claim {
                if claim.state?.isOpen == true {
                    ToolbarItem {
                        Button("Edit") { editing = true }
                    }
                }
                ToolbarItem {
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let claim { ClaimEditor(claim: claim, policy: policy) }
        }
        .sheet(isPresented: $addingSurveyor, onDismiss: assignAddedSurveyor) {
            NetworkEditor(route: NetworkRoute(kind: .surveyor))
        }
        .confirmationDialog("Delete claim #\(claimId)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete claim", role: .destructive) { Task { await deleteClaim() } }
        } message: {
            Text(assessments.isEmpty
                 ? "No surveyors are assigned to this claim."
                 : "\(counted(assessments.count, "survey assignment")) will be deleted too (ON DELETE CASCADE).")
        }
        .confirmationDialog("Reject claim #\(claimId)?", isPresented: $confirmingReject, titleVisibility: .visible) {
            Button("Reject claim", role: .destructive) { Task { await run { try await setStatus(.rejected) } } }
        } message: {
            Text("The claim closes with no payout and can't be edited afterwards.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorText ?? "")
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: assigns)
        .sensoryFeedback(.success, trigger: settles)
    }

    // MARK: - Data

    private var claim: Claim? { ledger.claims.first { $0.claimId == claimId } }
    private var policy: Policy? { ledger.policies.first { $0.policyNo == claim?.policyNo } }
    private var assessments: [AssessedBy] { ledger.assessedBy.filter { $0.claimId == claimId } }

    private var assigned: [Surveyor] {
        let ids = Set(assessments.map(\.surveyorId))
        return ledger.surveyors.filter { ids.contains($0.surveyorId) }
    }

    private var unassigned: [Surveyor] {
        let ids = Set(assessments.map(\.surveyorId))
        return ledger.surveyors.filter { !ids.contains($0.surveyorId) }
    }

    // MARK: - Hero

    private func hero(_ claim: Claim, state: ClaimStatus) -> some View {
        GlassCard(tint: state.tint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("CLAIM #\(claim.claimId)")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(state.tint)
                    Spacer()
                    StatusChip(text: state.label, tint: state.tint)
                        .contentTransition(.interpolate)
                }
                Text((claim.claimAmountValue ?? 0).money)
                    .font(.rounded(.largeTitle, weight: .bold))
                    .contentTransition(.numericText())
                    .accessibilityLabel("Claimed \((claim.claimAmountValue ?? 0).money)")
                ExposureBar(amount: claim.claimAmountValue ?? 0, limit: policy?.sumInsuredAmount, tint: state.tint)
                HStack {
                    Label(claim.lost?.dayText ?? "No loss date", systemImage: "calendar")
                        .font(.subheadline)
                        .accessibilityLabel("Loss date \(claim.lost?.dayText ?? "not set")")
                    Spacer()
                    if let no = claim.policyNo {
                        NavigationLink(value: AppRoute.policy(no)) {
                            Label("Policy #\(no)", systemImage: policy?.policyType?.symbol ?? "doc.text")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
    }

    // MARK: - Surveyors

    @ViewBuilder
    private func surveyors(open: Bool) -> some View {
        HStack {
            SectionHeader(title: "Surveyors", count: assigned.count)
            Spacer()
            if open {
                Menu {
                    ForEach(unassigned) { surveyor in
                        Button(surveyor.name) { Task { await assign(surveyor.surveyorId) } }
                    }
                    Divider()
                    Button("New surveyor…", systemImage: "plus") {
                        surveyorsBefore = Set(ledger.surveyors.map(\.surveyorId))
                        addingSurveyor = true
                    }
                } label: {
                    Label("Assign surveyor", systemImage: "person.badge.plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .disabled(busy)
            }
        }
        if assigned.isEmpty {
            Text(open ? "No surveyor yet. Assigning one moves the claim under survey." : "No surveyor was assigned.")
                .font(.callout)
                .foregroundStyle(Theme.inkMuted)
        }
        ForEach(assigned) { surveyor in
            HStack(spacing: 12) {
                NavigationLink(value: AppRoute.network(NetworkRoute(kind: .surveyor, key: surveyor.surveyorId))) {
                    HStack(spacing: 14) {
                        Monogram(name: surveyor.name, tint: NetworkKind.surveyor.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(surveyor.name)
                                .font(.rounded(.headline))
                            if let qualification = surveyor.qualification {
                                Text(qualification)
                                    .font(.caption)
                                    .foregroundStyle(Theme.inkMuted)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 4)
                    }
                    .contentShape(.rect)
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(.plain)
                if open {
                    Button("Remove \(surveyor.name)", systemImage: "xmark.circle.fill") {
                        Task { await remove(surveyor.surveyorId) }
                    }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(Theme.inkMuted)
                    .buttonStyle(.plain)
                    .disabled(busy)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            .padding(14)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    private func assignAddedSurveyor() {
        let added = ledger.surveyors.map(\.surveyorId).filter { !surveyorsBefore.contains($0) }
        guard let id = added.max() else { return }
        Task { await assign(id) }
    }

    // MARK: - Settlement

    @ViewBuilder
    private func settlement(_ claim: Claim, state: ClaimStatus) -> some View {
        SectionHeader(title: "Settlement")
        switch state {
        case .reported, .underSurvey:
            let estimate = PayoutEstimate(claimAmount: claim.claimAmountValue ?? 0, claimId: claim.claimId,
                                          policy: policy, claims: ledger.claims)
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    PayoutWaterfall(estimate: estimate)
                    VStack(spacing: 10) {
                        AmountLine(label: "Claimed", amount: estimate.claimAmount)
                        AmountLine(label: "Policy deductible", amount: estimate.deductibleCut, sign: "− ", tint: Theme.amber)
                        if estimate.limitCut > 0 {
                            AmountLine(label: "Over remaining limit", amount: estimate.limitCut, sign: "− ", tint: Theme.lavender)
                        }
                        Divider()
                        AmountLine(label: "Estimated payout", amount: estimate.payout, tint: Theme.teal, emphasised: true)
                    }
                    Text("Remaining aggregate limit \(estimate.remainingLimit.money): sum insured \(estimate.sumInsured.money) less \(estimate.otherSettled.money) paid on other claims under this policy.")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if state == .reported {
                        Label("Assign a surveyor before settling.", systemImage: "info.circle")
                            .font(.callout)
                            .foregroundStyle(Theme.amber)
                    }
                    HStack(spacing: 12) {
                        Button("Reject claim", role: .destructive) { confirmingReject = true }
                            .buttonStyle(.glass)
                            .tint(Theme.coral)
                        Button {
                            Task { await settle() }
                        } label: {
                            HStack {
                                if busy { ProgressView() }
                                Text("Settle claim")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.teal)
                        .disabled(state != .underSurvey || busy)
                        .accessibilityLabel("Settle claim")
                    }
                    .font(.rounded(.headline))
                    .controlSize(.large)
                    .disabled(busy)
                }
            }
            .transition(.opacity)
        case .settled:
            SettledCard(claim: claim)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
        case .rejected:
            GlassCard(tint: Theme.coral) {
                Label("Rejected. No payout was made.", systemImage: "xmark.seal.fill")
                    .font(.rounded(.headline))
                    .foregroundStyle(Theme.coral)
            }
        }
    }

    // MARK: - Actions

    private func run(_ work: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await work()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func setStatus(_ status: ClaimStatus) async throws {
        guard var updated = claim else { return }
        updated.status = status.rawValue
        try await ledger.save(updated, isNew: false)
    }

    /// Adds the ASSESSED_BY row; a reported claim then moves under survey.
    private func assign(_ surveyorId: Int) async {
        guard let claim, claim.state?.isOpen == true,
              !assessments.contains(where: { $0.surveyorId == surveyorId }) else { return }
        await run {
            try await ledger.save(AssessedBy(claimId: claimId, surveyorId: surveyorId), isNew: true)
            assigns += 1
            if claim.state == .reported { try await setStatus(.underSurvey) }
        }
    }

    private func remove(_ surveyorId: Int) async {
        guard let row = assessments.first(where: { $0.surveyorId == surveyorId }) else { return }
        await run { try await ledger.delete(row) }
    }

    private func settle() async {
        await run {
            let settled: Claim = try await APIClient.shared.action("claims/\(claimId)/settle")
            withAnimation(reduceMotion ? nil : .spring(duration: 0.5)) { ledger.upsert(settled) }
            settles += 1
        }
    }

    private func deleteClaim() async {
        guard let claim else { return }
        await run {
            try await ledger.delete(claim)
            dismiss()
        }
    }
}

// MARK: - Pieces

/// The server's settlement, with the payout and deductible counting up into place.
private struct SettledCard: View {
    let claim: Claim
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        let claimed = claim.claimAmountValue ?? 0
        let deductible = Decimal(apiString: claim.deductibleApplied) ?? 0
        let paid = claim.settledAmountValue ?? 0
        GlassCard(tint: Theme.teal) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Settled", systemImage: "checkmark.seal.fill")
                    .font(.rounded(.headline))
                    .foregroundStyle(Theme.teal)
                    .symbolEffect(.bounce, value: revealed)
                PayoutWaterfall(estimate: PayoutEstimate(claimAmount: claimed, deductible: deductible,
                                                         sumInsured: paid, otherSettled: 0),
                                marksLimit: false)
                VStack(spacing: 10) {
                    AmountLine(label: "Claimed", amount: claimed)
                    AmountLine(label: "Deductible applied", amount: revealed ? deductible : 0, sign: "− ", tint: Theme.amber)
                    Divider()
                    AmountLine(label: "Paid out", amount: revealed ? paid : 0, tint: Theme.teal, emphasised: true)
                }
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 1.2).delay(0.2)) { revealed = true }
        }
    }
}

/// Small edits to an open claim: loss date and amount.
private struct ClaimEditor: View {
    let claim: Claim
    let policy: Policy?

    var body: some View {
        EditSheet(title: "Claim", symbol: "lifepreserver.fill", tint: Theme.coral, isNew: false, item: claim,
                  isValid: { problem(with: $0) == nil }) { $claim in
            DatePicker("Loss date", selection: $claim.lossDate.day(default: APIDate.today()), displayedComponents: .date)
                .environment(\.timeZone, .gmt)
            TextField("Claim amount", value: $claim.claimAmount.decimalValue, format: .number)
                .keyboardType(.decimalPad)
                .font(.rounded(.body))
            if let problem = problem(with: claim) {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Theme.coral)
            } else if let limit = policy?.sumInsuredAmount {
                Text("Up to \(limit.money), the policy's sum insured.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
    }

    private func problem(with claim: Claim) -> String? {
        let amount = claim.claimAmountValue ?? 0
        if amount <= 0 { return "Enter an amount above zero." }
        if let limit = policy?.sumInsuredAmount, amount > limit {
            return "The amount can't be more than the sum insured (\(limit.money))."
        }
        return CoverageCheck(lossDay: claim.lossDate ?? APIDate.today(), issueDay: policy?.issueDate,
                             expiryDay: policy?.expiryDate).explanation
    }
}
