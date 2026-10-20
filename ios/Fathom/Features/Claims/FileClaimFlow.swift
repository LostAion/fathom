import SwiftUI

/// Guided flow for reporting a loss: policy, loss date, amount, review.
struct FileClaimFlow: View {
    /// Called with the new claim's id once the server has saved it.
    let onFiled: (Int) -> Void

    @Environment(Ledger.self) private var ledger
    @State private var policyNo: Int?
    @State private var lossDay = APIDate.today()
    /// Whole dollars as typed; non-digits are ignored.
    @State private var amountText = ""

    var body: some View {
        GuidedFlow(title: "File claim", tint: Theme.coral, steps: steps, finishLabel: "Submit claim", onFinish: submit) { step in
            switch step {
            case 0: policyPage
            case 1: datePage
            case 2: amountPage
            default: reviewPage
            }
        }
    }

    private var steps: [FlowStep] {
        [FlowStep(title: "Policy", prompt: "Which policy covers the loss?", isComplete: policy != nil),
         FlowStep(title: "Loss date", prompt: "When did the loss happen?", isComplete: coverage.isCovered),
         FlowStep(title: "Amount", prompt: "How much is being claimed?", isComplete: claimAmount > 0 && !overLimit),
         FlowStep(title: "Review", prompt: "Check the claim before it goes on the board")]
    }

    // MARK: - State

    /// Bound or active policies with a sum insured, newest first.
    private var claimable: [Policy] {
        ledger.policies
            .filter { $0.canTakeClaims && ($0.sumInsuredAmount ?? 0) > 0 }
            .sorted { $0.policyNo > $1.policyNo }
    }

    private var policy: Policy? { claimable.first { $0.policyNo == policyNo } }
    private var limit: Decimal { policy?.sumInsuredAmount ?? 0 }
    private var claimAmount: Decimal { Decimal(string: amountText.filter(\.isNumber)) ?? 0 }
    private var overLimit: Bool { claimAmount > limit }

    private var coverage: CoverageCheck {
        CoverageCheck(lossDay: lossDay, issueDay: policy?.issueDate, expiryDay: policy?.expiryDate)
    }

    private var estimate: PayoutEstimate {
        PayoutEstimate(claimAmount: claimAmount, claimId: 0, policy: policy, claims: ledger.claims)
    }

    private func choose(_ policy: Policy) {
        policyNo = policy.policyNo
        // Start on today, pulled inside the coverage period.
        var day = APIDate.today()
        if let issue = policy.issueDate, day < issue { day = issue }
        if let expiry = policy.expiryDate, day > expiry { day = expiry }
        lossDay = day
    }

    private func submit() async throws {
        guard let policy else { return }
        let claim = Claim(claimId: 0, lossDate: lossDay, claimAmount: claimAmount.apiString,
                          policyNo: policy.policyNo, status: ClaimStatus.reported.rawValue)
        let saved = try await ledger.save(claim, isNew: true)
        onFiled(saved.claimId)
    }

    // MARK: - Steps

    @ViewBuilder
    private var policyPage: some View {
        if claimable.isEmpty {
            GlassCard(tint: Theme.amber) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No policy can take a claim yet", systemImage: "shield.slash")
                        .font(.rounded(.headline))
                    Text("Claims attach to bound or active policies. Quote and bind a policy in the Policies tab first, then come back here.")
                        .font(.callout)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
        } else {
            Text("Only bound and active policies are shown. Swipe through and tap one.")
                .font(.callout)
                .foregroundStyle(Theme.inkMuted)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(claimable) { policy in
                        PolicyStackCard(policy: policy, selected: policy.policyNo == policyNo,
                                        settled: estimateForCard(policy))
                            .onTapGesture { withAnimation(.snappy) { choose(policy) } }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { choose(policy) }
                            .containerRelativeFrame(.horizontal) { width, _ in width * 0.8 }
                            .scrollTransition(axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.9)
                                    .rotation3DEffect(.degrees(phase.value * -12), axis: (x: 0, y: 1, z: 0))
                                    .opacity(phase.isIdentity ? 1 : 0.7)
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .sensoryFeedback(.selection, trigger: policyNo)
        }
    }

    private func estimateForCard(_ policy: Policy) -> Decimal {
        PayoutEstimate(claimAmount: 0, claimId: 0, policy: policy, claims: ledger.claims).otherSettled
    }

    @ViewBuilder
    private var datePage: some View {
        GlassCard {
            DatePicker("Loss date", selection: Binding(
                get: { APIDate.parse(lossDay) ?? .now },
                set: { lossDay = APIDate.string($0) }
            ), displayedComponents: .date)
            .datePickerStyle(.graphical)
            .tint(Theme.coral)
            .environment(\.timeZone, .gmt)
        }
        GlassCard(tint: coverage.isCovered ? Theme.teal : Theme.coral) {
            VStack(alignment: .leading, spacing: 12) {
                Label(coverage.isCovered ? "Inside the coverage period" : "Outside the coverage period",
                      systemImage: coverage.isCovered ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.rounded(.headline))
                    .foregroundStyle(coverage.isCovered ? Theme.teal : Theme.coral)
                    .contentTransition(.symbolEffect(.replace))
                CoverageStrip(issueDay: policy?.issueDate, expiryDay: policy?.expiryDate, lossDay: lossDay)
                if let explanation = coverage.explanation {
                    Text(explanation)
                        .font(.callout)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .animation(.snappy, value: coverage)
    }

    @ViewBuilder
    private var amountPage: some View {
        let estimate = estimate
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text("$")
                        .foregroundStyle(Theme.inkMuted)
                    TextField("0", text: $amountText)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("Claim amount")
                        .accessibilityIdentifier("Claim amount")
                }
                .font(.rounded(.largeTitle, weight: .bold))
                Text(overLimit ? "More than the \(limit.money) sum insured" : "Up to \(limit.money) (sum insured)")
                    .font(.callout)
                    .foregroundStyle(overLimit ? Theme.coral : Theme.inkMuted)
            }
        }
        GlassCard(tint: Theme.teal) {
            VStack(spacing: 10) {
                AmountLine(label: "Claimed", amount: estimate.claimAmount)
                AmountLine(label: "Deductible", amount: estimate.deductibleCut, sign: "− ", tint: Theme.amber)
                if estimate.limitCut > 0 {
                    AmountLine(label: "Over remaining limit", amount: estimate.limitCut, sign: "− ", tint: Theme.lavender)
                }
                Divider()
                AmountLine(label: "Estimated payout", amount: estimate.payout, tint: Theme.teal, emphasised: true)
            }
            .animation(.snappy, value: estimate)
        }
    }

    @ViewBuilder
    private var reviewPage: some View {
        if let policy {
            GlassCard(tint: Theme.coral) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("New claim", systemImage: "lifepreserver.fill")
                            .font(.rounded(.headline))
                            .foregroundStyle(Theme.coral)
                        Spacer()
                        StatusChip(text: ClaimStatus.reported.label, tint: ClaimStatus.reported.tint)
                    }
                    reviewLine("Policy", "Policy #\(policy.policyNo) · \(policy.policyType?.displayName ?? "Cover")")
                    reviewLine("Loss date", APIDate.parse(lossDay)?.dayText ?? lossDay)
                    reviewLine("Claimed", claimAmount.money)
                    reviewLine("Deductible", (policy.deductibleAmount ?? 0).money)
                    reviewLine("Estimated payout", estimate.payout.money)
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "If settled as filed")
                    PayoutWaterfall(estimate: estimate)
                    Text("The server works out the final payout when the claim is settled.")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
        }
    }

    private func reviewLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(Theme.inkMuted)
            Spacer()
            Text(value)
                .font(.rounded(.body, weight: .semibold))
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Pieces

/// One policy in the picker's card stack.
private struct PolicyStackCard: View {
    let policy: Policy
    let selected: Bool
    /// Already paid on this policy's settled claims.
    let settled: Decimal

    var body: some View {
        let type = policy.policyType ?? .hull
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: type.symbol)
                    .font(.title)
                    .foregroundStyle(type.tint)
                Spacer()
                if let status = policy.lifecycle {
                    StatusChip(text: status.rawValue, tint: status.tint)
                }
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? Theme.coral : Theme.inkMuted)
                    .contentTransition(.symbolEffect(.replace))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("POLICY #\(policy.policyNo)")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(type.tint)
                Text(type.displayName)
                    .font(.rounded(.title3, weight: .bold))
            }
            HStack(alignment: .top) {
                figure("Sum insured", policy.sumInsuredAmount?.compactMoney ?? "–")
                Spacer()
                figure("Deductible", policy.deductibleAmount?.compactMoney ?? "–")
                Spacer()
                figure("Paid so far", settled.compactMoney)
            }
            Text("\(policy.issued?.dayText ?? "Open") to \(policy.expires?.dayText ?? "open")")
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
        }
        .padding(18)
        .glassEffect(.regular.tint(type.tint.opacity(selected ? 0.3 : 0.1)).interactive(), in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Theme.coral, lineWidth: selected ? 2 : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Policy #\(policy.policyNo), \(type.displayName), sum insured \(policy.sumInsuredAmount?.money ?? "not set")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.inkMuted)
            Text(value)
                .font(.rounded(.headline, weight: .semibold))
        }
    }
}
