import SwiftUI

/// Incident board: every claim as a card, newest loss first.
struct ClaimsView: View {
    @Environment(Ledger.self) private var ledger
    /// nil shows every status.
    @State private var filter: ClaimStatus?
    @State private var path = NavigationPath()
    @State private var filing = false
    @State private var filedClaim: Int?

    var body: some View {
        NavigationStack(path: $path) {
            Screen(title: "Claims", subtitle: "Incidents and settlements") {
                LedgerStatusCard()
                if ledger.hasLoaded {
                    SummaryStrip(summary: ClaimBoardSummary(claims: ledger.claims))
                    FilterChips(selection: $filter, counts: ClaimBoardSummary(claims: ledger.claims).counts,
                                total: ledger.claims.count)
                    board
                        .animation(.snappy, value: filter)
                }
            }
            .refreshable { await ledger.refresh() }
            .overlay(alignment: .bottomTrailing) { fileButton }
            .toolbar(.hidden, for: .navigationBar)
            .appRoutes()
        }
        .fullScreenCover(isPresented: $filing, onDismiss: openFiledClaim) {
            FileClaimFlow { filedClaim = $0 }
        }
    }

    // MARK: - Board

    private var visibleClaims: [Claim] {
        ClaimSorting.newestFirst(ledger.claims.filter { filter == nil || $0.state == filter })
    }

    @ViewBuilder
    private var board: some View {
        let claims = visibleClaims
        VStack(spacing: 12) {
            if claims.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(filter == nil ? "No claims on the board" : "No \(filter!.label.lowercased()) claims",
                              systemImage: "lifepreserver")
                            .font(.rounded(.headline))
                        Text(filter == nil ? "Clear waters so far. File a claim when a loss is reported." : "Try another filter.")
                            .font(.callout)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            ForEach(claims) { claim in
                NavigationLink(value: AppRoute.claim(claim.claimId)) {
                    ClaimCard(claim: claim, policy: policy(for: claim), surveyors: surveyorNames(for: claim))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.bottom, 60)
    }

    private var fileButton: some View {
        Button("File claim", systemImage: "plus") { filing = true }
            .font(.rounded(.headline))
            .buttonStyle(.glassProminent)
            .tint(Theme.coral)
            .padding(20)
    }

    private func openFiledClaim() {
        guard let id = filedClaim else { return }
        filedClaim = nil
        path.append(AppRoute.claim(id))
    }

    // MARK: - Lookups

    private func policy(for claim: Claim) -> Policy? {
        ledger.policies.first { $0.policyNo == claim.policyNo }
    }

    private func surveyorNames(for claim: Claim) -> [String] {
        let ids = ledger.assessedBy.filter { $0.claimId == claim.claimId }.map(\.surveyorId)
        return ledger.surveyors.filter { ids.contains($0.surveyorId) }.map(\.name)
    }
}

// MARK: - Pieces

/// Open exposure, settled total and the status mix.
private struct SummaryStrip: View {
    let summary: ClaimBoardSummary

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    stat("Open exposure", summary.openExposure, tint: Theme.amber,
                         note: "Reported and under survey")
                    Spacer()
                    stat("Settled", summary.settledTotal, tint: Theme.teal, note: "Paid out")
                }
                StatusMix(counts: summary.counts)
            }
        }
    }

    private func stat(_ title: String, _ amount: Decimal, tint: Color, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(tint)
            Text(amount.compactMoney)
                .font(.rounded(.title, weight: .bold))
                .contentTransition(.numericText())
            Text(note)
                .font(.caption2)
                .foregroundStyle(Theme.inkMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(amount.money), \(note.lowercased())")
    }
}

/// One bar split by how many claims are in each status, with a legend.
private struct StatusMix: View {
    let counts: [ClaimStatus: Int]

    var body: some View {
        let total = max(1, counts.values.reduce(0, +))
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    ForEach(ClaimStatus.allCases, id: \.self) { status in
                        let count = counts[status] ?? 0
                        if count > 0 {
                            Capsule()
                                .fill(status.tint.gradient)
                                .frame(width: max(6, (proxy.size.width - 9) * CGFloat(count) / CGFloat(total)))
                        }
                    }
                }
            }
            .frame(height: 8)
            .background(Capsule().fill(Theme.inkMuted.opacity(0.15)))
            HStack(spacing: 12) {
                ForEach(ClaimStatus.allCases, id: \.self) { status in
                    HStack(spacing: 4) {
                        Circle().fill(status.tint).frame(width: 7, height: 7)
                        Text("\(counts[status] ?? 0)")
                            .font(.rounded(.caption, weight: .bold))
                            .contentTransition(.numericText())
                        Text(status.label)
                            .font(.caption2)
                            .foregroundStyle(Theme.inkMuted)
                            .lineLimit(1)
                    }
                }
            }
            .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Claims by status")
        .accessibilityValue(ClaimStatus.allCases.map { "\(counts[$0] ?? 0) \($0.label.lowercased())" }.joined(separator: ", "))
    }
}

private struct FilterChips: View {
    @Binding var selection: ClaimStatus?
    let counts: [ClaimStatus: Int]
    let total: Int

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    chip("All", count: total, tint: Theme.teal, value: nil)
                    ForEach(ClaimStatus.allCases, id: \.self) { status in
                        chip(status.label, count: counts[status] ?? 0, tint: status.tint, value: status)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func chip(_ title: String, count: Int, tint: Color, value: ClaimStatus?) -> some View {
        let selected = value == selection
        return Button {
            withAnimation(.snappy) { selection = value }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                Text("\(count)")
                    .foregroundStyle(selected ? tint : Theme.inkMuted)
                    .contentTransition(.numericText())
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(tint.opacity(0.3)).interactive() : .regular.interactive(), in: .capsule)
        .accessibilityLabel(title)
        .accessibilityValue("\(count)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
