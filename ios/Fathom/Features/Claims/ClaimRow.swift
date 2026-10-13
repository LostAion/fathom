import SwiftUI

extension ClaimStatus {
    var label: String {
        switch self {
        case .reported: "Reported"
        case .underSurvey: "Under survey"
        case .settled: "Settled"
        case .rejected: "Rejected"
        }
    }

    var tint: Color {
        switch self {
        case .reported: Theme.amber
        case .underSurvey: Theme.sky
        case .settled: Theme.teal
        case .rejected: Theme.coral
        }
    }
}

/// One-line claim summary used wherever a screen links to claims.
struct ClaimRow: View {
    let claim: Claim

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "lifepreserver.fill")
                .font(.title3)
                .foregroundStyle(Theme.coral)
                .frame(width: 44, height: 44)
                .background(Theme.coral.opacity(0.15), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text("Claim #\(claim.claimId)")
                    .font(.rounded(.headline))
                Text([claim.policyNo.map { "Policy #\($0)" }, claim.lost?.formatted(date: .abbreviated, time: .omitted)]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(claim.claimAmountValue?.compactMoney ?? "–")
                    .font(.rounded(.subheadline, weight: .semibold))
                if let state = claim.state {
                    StatusChip(text: state.label, tint: state.tint)
                }
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}
