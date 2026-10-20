import SwiftUI

/// Wallet pass for one policy: type art, number, client, money, status and cover dates.
struct PolicyCard: View {
    let policy: Policy
    let clientName: String?
    var today = PolicyMath.today()

    var body: some View {
        let type = policy.policyType ?? .hull
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label(type.displayName, systemImage: type.symbol)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(type.tint)
                Spacer(minLength: 8)
                StatusChip(text: PolicyFormat.stage(policy.stage), tint: policy.stage.tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("#\(policy.policyNo)")
                    .font(.system(.title, design: .monospaced, weight: .bold))
                    .accessibilityLabel(policy.numberTitle)
                Text(clientName ?? "No client")
                    .font(.rounded(.headline))
                    .foregroundStyle(clientName == nil ? Theme.inkMuted : Theme.ink)
                    .lineLimit(2)
            }

            HStack(alignment: .bottom, spacing: 22) {
                figure("Sum insured", policy.sumInsuredAmount?.compactMoney, large: true)
                figure("Premium", policy.premiumAmount?.compactMoney)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Label("\(PolicyFormat.day(policy.issued)) → \(PolicyFormat.day(policy.expires))", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                Spacer(minLength: 0)
                expiryBadge
            }
        }
        .padding(20)
        .background(alignment: .bottomTrailing) {
            PolicyArt(type: type)
                .frame(width: 150)
                .opacity(0.28)
                .offset(x: 18, y: type == .pi ? 30 : 6)
        }
        .clipShape(.rect(cornerRadius: 26))
        .background {
            LinearGradient(colors: [type.tint.opacity(0.28), type.tint.opacity(0.04)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(.rect(cornerRadius: 26))
        }
        .contentShape(.rect(cornerRadius: 26))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
        .accessibilityElement(children: .combine)
    }

    private func figure(_ label: String, _ value: String?, large: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value ?? "–")
                .font(.rounded(large ? .title2 : .headline, weight: .bold))
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.inkMuted)
        }
    }

    @ViewBuilder
    private var expiryBadge: some View {
        if policy.stage != .cancelled {
            switch PolicyMath.expiry(of: policy.expires, today: today) {
            case .expiring(let days):
                badge(days == 0 ? "Expires today" : "Expires in \(counted(days, "day"))", tint: Theme.amber, symbol: "hourglass")
            case .expired:
                badge("Expired", tint: Theme.coral, symbol: "clock.badge.xmark")
            case .running, .unknown:
                EmptyView()
            }
        }
    }

    private func badge(_ text: String, tint: Color, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.16), in: .capsule)
    }
}
