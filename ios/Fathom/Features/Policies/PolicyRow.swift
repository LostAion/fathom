import SwiftUI

extension PolicyType {
    var symbol: String {
        switch self {
        case .hull: "ferry.fill"
        case .cargo: "shippingbox.fill"
        case .pi: "shield.lefthalf.filled"
        }
    }

    var tint: Color {
        switch self {
        case .hull: Theme.sky
        case .cargo: Theme.amber
        case .pi: Theme.lavender
        }
    }
}

extension PolicyStatus {
    var tint: Color {
        switch self {
        case .draft: Theme.inkMuted
        case .quoted: Theme.amber
        case .bound, .active: Theme.teal
        case .cancelled: Theme.coral
        }
    }
}

/// One-line policy summary used wherever a screen links to policies.
struct PolicyRow: View {
    let policy: Policy
    /// Replaces the status chip, e.g. a reinsurer's share of this policy.
    var detail: String?

    var body: some View {
        let type = policy.policyType ?? .hull
        HStack(spacing: 14) {
            Image(systemName: type.symbol)
                .font(.title3)
                .foregroundStyle(type.tint)
                .frame(width: 44, height: 44)
                .background(type.tint.opacity(0.15), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text("Policy #\(policy.policyNo)")
                    .font(.rounded(.headline))
                Text(type.displayName)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(policy.sumInsuredAmount?.compactMoney ?? "–")
                    .font(.rounded(.subheadline, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                } else if let status = policy.lifecycle {
                    StatusChip(text: status.rawValue, tint: status.tint)
                }
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}
