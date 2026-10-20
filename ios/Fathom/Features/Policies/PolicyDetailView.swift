import SwiftUI

/// One policy: cover period, lifecycle, money, the records around it, reinsurance and claims.
struct PolicyDetailView: View {
    let policyNo: Int

    @Environment(Ledger.self) private var ledger
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editing = false
    @State private var buildingShares = false
    @State private var confirmingDelete = false
    @State private var confirmingCancel = false
    @State private var working = false
    @State private var actionError: String?
    @State private var seals = 0
    @State private var showWebAsList: Bool?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let policy {
                    let links = PolicyLinks(policy, in: ledger)
                    hero(links)
                    coverage(policy)
                    lifecycle(policy)
                    UnderwritingCard(policy: policy)
                    financials(policy)
                    relationships(links)
                    reinsurance(links)
                    claims(links.claims)
                } else if ledger.hasLoaded {
                    ContentUnavailableView("Policy removed", systemImage: "shield.slash",
                                           description: Text("Policy #\(policyNo) is no longer on file."))
                } else {
                    LedgerStatusCard()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .foregroundStyle(Theme.ink)
        .background { SonarBackground() }
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await ledger.refresh() }
        .toolbar {
            if policy != nil {
                ToolbarItem {
                    Button("Edit") { editing = true }
                }
                ToolbarItem {
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let policy { PolicyEditor(policy: policy) }
        }
        .sheet(isPresented: $buildingShares) {
            if let policy {
                ReinsuranceBuilder(policy: policy, existing: ledger.reinsuredBy.filter { $0.policyNo == policyNo })
            }
        }
        .confirmationDialog("Delete policy #\(policyNo)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete policy", role: .destructive) { Task { await delete() } }
        } message: {
            Text(deleteEffect)
        }
        .confirmationDialog("Cancel policy #\(policyNo)?", isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("Cancel policy", role: .destructive) { Task { await cancel() } }
            Button("Keep policy", role: .cancel) {}
        } message: {
            Text("The policy stays on file as cancelled and can no longer be quoted or bound.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK") {}
        } message: {
            Text(actionError ?? "")
        }
        .sensoryFeedback(.success, trigger: seals)
    }

    private var policy: Policy? { ledger.policies.first { $0.policyNo == policyNo } }
    private var today: Date { PolicyMath.today() }

    // MARK: - Hero

    private func hero(_ links: PolicyLinks) -> some View {
        let policy = links.policy
        let type = policy.policyType ?? .hull
        return GlassCard(tint: type.tint) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(type.displayName, systemImage: type.symbol)
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(type.tint)
                    Text("#\(policy.policyNo)")
                        .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                        .accessibilityLabel(policy.numberTitle)
                        .accessibilityIdentifier("policy-number")
                    Text(links.client?.name ?? "No client")
                        .font(.rounded(.headline))
                    StatusChip(text: PolicyFormat.stage(policy.stage), tint: policy.stage.tint)
                        .contentTransition(.interpolate)
                        .accessibilityIdentifier("policy-status")
                }
                Spacer(minLength: 0)
                PolicyArt(type: type)
                    .frame(width: 110)
            }
        }
        .overlay(alignment: .topTrailing) {
            if policy.stage == .bound || policy.stage == .active {
                SealStamp()
                    .offset(x: 8, y: -14)
                    .transition(reduceMotion ? .opacity : .scale(scale: 2.6).combined(with: .opacity))
            }
        }
    }

    // MARK: - Coverage

    private func coverage(_ policy: Policy) -> some View {
        let state = PolicyMath.expiry(of: policy.expires, today: today)
        let progress = PolicyMath.coverageProgress(issue: policy.issued, expiry: policy.expires, today: today)
        let (remaining, tint): (String, Color) = switch state {
        case .unknown: ("No expiry date", Theme.inkMuted)
        case .expired(let days): ("Expired \(counted(days, "day")) ago", Theme.coral)
        case .expiring(let days): (days == 0 ? "Expires today" : "\(counted(days, "day")) left", Theme.amber)
        case .running(let days):
            if let issued = policy.issued, issued > today {
                ("Starts in \(counted(PolicyMath.days(from: today, to: issued), "day"))", Theme.sky)
            } else {
                ("\(counted(days, "day")) left", Theme.teal)
            }
        }

        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: "Coverage")
                    Spacer()
                    Text(remaining)
                        .font(.rounded(.subheadline, weight: .semibold))
                        .foregroundStyle(tint)
                }
                if let progress {
                    CoverageBar(progress: progress, tint: tint)
                        .padding(.top, 18)
                }
                HStack {
                    dateColumn("Issued", policy.issued, alignment: .leading)
                    Spacer()
                    dateColumn("Expires", policy.expires, alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func dateColumn(_ label: String, _ date: Date?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
            Text(PolicyFormat.day(date))
                .font(.rounded(.subheadline, weight: .semibold))
        }
    }

    // MARK: - Lifecycle

    private func lifecycle(_ policy: Policy) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Lifecycle")
                LifecycleStepper(stage: policy.stage)
                if policy.stage == .cancelled {
                    Label("This policy was cancelled.", systemImage: "xmark.octagon.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.coral)
                } else {
                    HStack(spacing: 12) {
                        if policy.stage == .draft {
                            actionButton("Quote", symbol: "doc.text.fill", tint: Theme.amber) { await advance("quote") }
                        }
                        if policy.stage == .quoted {
                            actionButton("Bind", symbol: "seal.fill", tint: Theme.teal) { await advance("bind") }
                                .disabled(policy.underwritingBlocksBinding)
                        }
                        Button("Cancel policy", role: .destructive) { confirmingCancel = true }
                            .buttonStyle(.glass)
                            .tint(Theme.coral)
                            .disabled(working)
                    }
                    .font(.rounded(.headline))
                    .controlSize(.large)
                }
            }
        }
    }

    private func actionButton(_ title: String, symbol: String, tint: Color, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack {
                if working { ProgressView() } else { Image(systemName: symbol) }
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(tint)
        .disabled(working)
        .accessibilityLabel(title)
    }

    // MARK: - Financials

    private func financials(_ policy: Policy) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Financials")
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
                          alignment: .leading, spacing: 16) {
                    figure("Sum insured", policy.sumInsuredAmount?.money, tint: Theme.teal)
                    figure("Premium", policy.premiumAmount?.money, tint: Theme.amber)
                    figure("Rate on line",
                           PolicyMath.rateOnLine(premium: policy.premiumAmount, sumInsured: policy.sumInsuredAmount).map(PolicyFormat.percent),
                           tint: Theme.amber)
                    figure("Deductible", policy.deductibleAmount?.money, tint: Theme.coral)
                    if let extra = policy.typeSpecific {
                        figure(extra.label, extra.value, tint: (policy.policyType ?? .hull).tint)
                    }
                }
            }
        }
    }

    private func figure(_ label: String, _ value: String?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
            Text(value ?? "Not set")
                .font(.rounded(.headline, weight: .bold))
                .foregroundStyle(value == nil ? Theme.inkMuted : Theme.ink)
                .contentTransition(.numericText())
            Capsule()
                .fill(tint.opacity(0.6))
                .frame(width: 24, height: 3)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Relationships

    private func relationships(_ links: PolicyLinks) -> some View {
        let nodes = PolicyWebNode.nodes(for: links)
        let asList = showWebAsList ?? (voiceOver || typeSize.isAccessibilitySize)
        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: "Relationships", count: nodes.count)
                    Spacer()
                    Picker("Show as", selection: Binding(get: { asList }, set: { showWebAsList = $0 })) {
                        Label("Web", systemImage: "circle.hexagongrid").tag(false)
                        Label("List", systemImage: "list.bullet").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.iconOnly)
                    .fixedSize()
                }
                if nodes.isEmpty {
                    Text("Nothing is linked to this policy yet.")
                        .font(.callout)
                        .foregroundStyle(Theme.inkMuted)
                } else if asList {
                    RelationshipList(nodes: nodes)
                } else {
                    RelationshipWeb(policy: links.policy, nodes: nodes)
                        .id(nodes.map(\.id))
                }
            }
        }
    }

    // MARK: - Reinsurance

    private func reinsurance(_ links: PolicyLinks) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: "Reinsurance", count: links.shares.count)
                    Spacer()
                    Button("Edit shares", systemImage: "slider.horizontal.3") { buildingShares = true }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.glass)
                        .tint(Theme.lavender)
                }
                if links.shares.isEmpty {
                    Text("Fully retained. No reinsurance placed yet.")
                        .font(.callout)
                        .foregroundStyle(Theme.inkMuted)
                }
                ReinsuranceDonut(links: links)
            }
        }
    }

    // MARK: - Claims

    @ViewBuilder
    private func claims(_ claims: [Claim]) -> some View {
        SectionHeader(title: "Claims", count: claims.count)
        if claims.isEmpty {
            GlassCard {
                Label("No claims on this policy", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(Theme.teal)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(claims.enumerated()), id: \.element.id) { index, claim in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(claim.state?.tint ?? Theme.coral)
                                .frame(width: 12, height: 12)
                                .padding(.top, 30)
                            Rectangle()
                                .fill(Theme.coral.opacity(0.35))
                                .frame(width: 2)
                                .opacity(index == claims.count - 1 ? 0 : 1)
                        }
                        .accessibilityHidden(true)
                        NavigationLink(value: AppRoute.claim(claim.claimId)) {
                            ClaimRow(claim: claim)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 10)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private var deleteEffect: String {
        let claims = ledger.claims.count { $0.policyNo == policyNo }
        let shares = ledger.reinsuredBy.count { $0.policyNo == policyNo }
        if claims == 0 && shares == 0 { return "No claims or reinsurance shares are linked to this policy." }
        return "\(counted(claims, "claim")) and \(counted(shares, "reinsurance share")) will be deleted too (ON DELETE CASCADE)."
    }

    private func advance(_ action: String) async {
        working = true
        defer { working = false }
        do {
            let updated: Policy = try await APIClient.shared.action("policies/\(policyNo)/\(action)")
            withAnimation(reduceMotion ? .default : .spring(response: 0.4, dampingFraction: 0.55)) {
                ledger.upsert(updated)
            }
            if updated.stage == .bound { seals += 1 }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func cancel() async {
        guard var updated = policy else { return }
        working = true
        defer { working = false }
        updated.status = PolicyStatus.cancelled.rawValue
        do {
            let saved = try await APIClient.shared.update(updated)
            withAnimation { ledger.upsert(saved) }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func delete() async {
        guard let policy else { return }
        do {
            try await ledger.delete(policy)
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

// MARK: - Pieces

/// Issue to expiry as a bar, filled up to today, with a marker for today.
private struct CoverageBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        Capsule()
            .fill(Theme.inkMuted.opacity(0.2))
            .frame(height: 10)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(10, geo.size.width * progress))
                    VStack(spacing: 2) {
                        Text("Today")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(tint)
                            .fixedSize()
                        Capsule()
                            .fill(Theme.ink)
                            .frame(width: 3, height: 22)
                    }
                    .position(x: geo.size.width * progress, y: -4)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Cover used")
            .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
    }
}

/// DRAFT → QUOTED → BOUND as three stops on a line.
private struct LifecycleStepper: View {
    let stage: PolicyStatus
    private let stops: [PolicyStatus] = [.draft, .quoted, .bound]

    private var reached: Int {
        switch stage {
        case .draft, .cancelled: 0
        case .quoted: 1
        case .bound, .active: 2
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                if index > 0 {
                    Capsule()
                        .fill(index <= reached && stage != .cancelled ? stop.tint : Theme.inkMuted.opacity(0.25))
                        .frame(height: 3)
                        .padding(.bottom, 22)
                }
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(index <= reached && stage != .cancelled ? stop.tint : Theme.inkMuted.opacity(0.18))
                            .frame(width: 30, height: 30)
                        Image(systemName: index < reached ? "checkmark" : symbol(stop))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(index <= reached && stage != .cancelled ? Theme.abyss : Theme.inkMuted)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .symbolEffect(.bounce, value: reached)
                    Text(PolicyFormat.stage(stop))
                        .font(.caption.weight(index == reached ? .bold : .regular))
                        .foregroundStyle(index == reached ? Theme.ink : Theme.inkMuted)
                        .fixedSize()
                }
            }
        }
        .animation(.spring(duration: 0.4), value: reached)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lifecycle")
        .accessibilityValue(stage == .cancelled ? "Cancelled" : "\(PolicyFormat.stage(stage)), step \(reached + 1) of 3")
    }

    private func symbol(_ stop: PolicyStatus) -> String {
        switch stop {
        case .draft: "pencil"
        case .quoted: "doc.text"
        default: "seal"
        }
    }
}

/// Rubber stamp pressed onto the hero card when a policy is bound.
private struct SealStamp: View {
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.teal, lineWidth: 3)
            Circle()
                .strokeBorder(Theme.teal.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .padding(6)
            VStack(spacing: 0) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16))
                Text("BOUND")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(1.5)
            }
            .foregroundStyle(Theme.teal)
        }
        .frame(width: 78, height: 78)
        .background(Theme.abyss.opacity(0.75), in: .circle)
        .rotationEffect(.degrees(-14))
        .accessibilityElement()
        .accessibilityLabel("Bound")
        .accessibilityIdentifier("bound-seal")
    }
}
