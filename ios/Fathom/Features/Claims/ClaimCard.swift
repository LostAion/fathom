import SwiftUI

/// Incident card on the claims board, tinted by status.
struct ClaimCard: View {
    let claim: Claim
    let policy: Policy?
    let surveyors: [String]

    var body: some View {
        let state = claim.state ?? .reported
        let type = policy?.policyType
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("CLAIM #\(claim.claimId)")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(state.tint)
                Spacer()
                StatusChip(text: state.label, tint: state.tint)
            }
            HStack(spacing: 12) {
                Image(systemName: type?.symbol ?? "doc.text")
                    .font(.title3)
                    .foregroundStyle(type?.tint ?? Theme.inkMuted)
                    .frame(width: 40, height: 40)
                    .background((type?.tint ?? Theme.inkMuted).opacity(0.15), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(claim.policyNo.map { "Policy #\($0)" } ?? "No policy")
                        .font(.rounded(.headline))
                    Text(type?.displayName ?? "Unknown cover")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Loss")
                        .font(.caption2)
                        .foregroundStyle(Theme.inkMuted)
                    Text(claim.lost?.dayText ?? "No date")
                        .font(.rounded(.subheadline, weight: .semibold))
                }
            }
            ExposureBar(amount: claim.claimAmountValue ?? 0, limit: policy?.sumInsuredAmount, tint: state.tint)
            HStack {
                SurveyorStack(names: surveyors, size: 26)
                if surveyors.isEmpty {
                    Text("Awaiting surveyor")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                if state == .settled, let paid = claim.settledAmountValue {
                    Label("Paid \(paid.money)", systemImage: "checkmark.seal.fill")
                        .font(.rounded(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.teal)
                }
            }
        }
        .padding(16)
        .background(alignment: .leading) {
            Rectangle().fill(state.tint.gradient).frame(width: 4)
        }
        .clipShape(.rect(cornerRadius: 22))
        .contentShape(.rect(cornerRadius: 22))
        .glassEffect(.regular.tint(state.tint.opacity(0.12)).interactive(), in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}
