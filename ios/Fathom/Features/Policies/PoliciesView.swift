import SwiftUI

/// The policy wallet: one pass per policy, newest first. Cards that scroll past the
/// top pin and sink under the next one, like a stack of passes.
struct PoliciesView: View {
    @Environment(Ledger.self) private var ledger
    @State private var filter = PolicyFilter.all
    @State private var path = NavigationPath()
    @State private var issuing = false
    @State private var issuedNo: Int?

    var body: some View {
        NavigationStack(path: $path) {
            Screen(title: "Policies", subtitle: subtitle) {
                FilterChips(selection: $filter) { option in
                    ledger.policies.count { option.matches($0, today: today) }
                }
                LedgerStatusCard()
                wallet
                    .animation(.snappy, value: filter)
            }
            .refreshable { await ledger.refresh() }
            .overlay(alignment: .bottomTrailing) { issueButton }
            .toolbar(.hidden, for: .navigationBar)
            .appRoutes()
            .fullScreenCover(isPresented: $issuing, onDismiss: openIssued) {
                IssuePolicyFlow { issuedNo = $0 }
            }
        }
    }

    private var today: Date { PolicyMath.today() }

    private var shown: [Policy] {
        ledger.policies
            .filter { filter.matches($0, today: today) }
            .sorted { $0.policyNo > $1.policyNo }
    }

    private var subtitle: String {
        let insured = ledger.policies.filter { $0.stage != .cancelled }.compactMap(\.sumInsuredAmount).reduce(0, +)
        return "\(counted(ledger.policies.count, "policy", "policies")) · \(insured.compactMoney) insured"
    }

    @ViewBuilder
    private var wallet: some View {
        let policies = shown
        if ledger.hasLoaded && policies.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label(filter == .all ? "No policies yet" : "No \(filter.title.lowercased()) policies",
                          systemImage: filter.symbol)
                        .font(.rounded(.headline))
                    Text(filter == .all ? "Tap New policy to create your first one." : "Try another filter.")
                        .font(.callout)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
        }
        VStack(spacing: 14) {
            ForEach(policies) { policy in
                NavigationLink(value: AppRoute.policy(policy.policyNo)) {
                    PolicyCard(policy: policy,
                               clientName: ledger.clients.first { $0.id == policy.clientId }?.name,
                               today: today)
                }
                .buttonStyle(.plain)
                .modifier(WalletStacking())
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        // Room for the floating button.
        Color.clear.frame(height: 56)
    }

    private var issueButton: some View {
        Button("New policy", systemImage: "plus") { issuing = true }
            .font(.rounded(.headline))
            .buttonStyle(.glassProminent)
            .tint(Theme.teal)
            .padding(20)
    }

    private func openIssued() {
        guard let issuedNo else { return }
        self.issuedNo = nil
        path.append(AppRoute.policy(issuedNo))
    }
}

/// Pins a card once it reaches the top of the scroll view and shrinks and fades it
/// as the next card slides over it.
private struct WalletStacking: ViewModifier {
    func body(content: Content) -> some View {
        content.visualEffect { effect, proxy in
            let pinLine: CGFloat = 64
            let overshoot = max(0, pinLine - proxy.frame(in: .scrollView).minY)
            let progress = min(1, overshoot / max(proxy.size.height, 1))
            return effect
                .scaleEffect(1 - 0.08 * progress, anchor: .top)
                .offset(y: overshoot)
                .opacity(1 - progress)
        }
    }
}

private struct FilterChips: View {
    @Binding var selection: PolicyFilter
    let count: (PolicyFilter) -> Int

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(PolicyFilter.allCases) { option in
                        let selected = option == selection
                        Button {
                            withAnimation(.snappy) { selection = option }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: option.symbol)
                                Text(option.title)
                                Text("\(count(option))")
                                    .foregroundStyle(selected ? option.tint : Theme.inkMuted)
                                    .contentTransition(.numericText())
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(selected ? .regular.tint(option.tint.opacity(0.3)).interactive() : .regular.interactive(), in: .capsule)
                        .accessibilityLabel(option.title)
                        .accessibilityValue("\(count(option))")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: selection)
    }
}
