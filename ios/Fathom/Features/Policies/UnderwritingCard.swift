import SwiftUI

struct UnderwritingCard: View {
    let policy: Policy
    @Environment(Ledger.self) private var ledger
    @State private var assessing = false

    var body: some View {
        GlassCard(tint: Theme.amber) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Underwriting")
                Text("Coursework demo using local sanctions fixtures and route rules.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                if let decision = policy.underwritingDecision {
                    Text(decision.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.rounded(.headline))
                        .foregroundStyle(policy.underwritingBlocksBinding ? Theme.coral : Theme.teal)
                        .accessibilityIdentifier("underwriting-decision")
                    if let score = policy.riskScore {
                        LabeledContent("Risk score", value: "\(score) / 100")
                    }
                    if let surcharge = Decimal(apiString: policy.awrpSurcharge) {
                        LabeledContent("Route surcharge", value: "\(surcharge.apiString)%")
                    }
                    if policy.underwritingBlocksBinding {
                        Text("Binding is blocked. Review the risk factors with a senior underwriter.")
                            .font(.callout)
                            .foregroundStyle(Theme.coral)
                    }
                    if let report = policy.underwritingReport {
                        LabeledContent("Suggested premium", value: Decimal(report.recommendedPremium).money)
                        LabeledContent("Vessel age assessed", value: "\(report.vesselAge) years")
                        if let voyageId = report.voyageId,
                           let voyage = ledger.voyages.first(where: { $0.id == voyageId }) {
                            Text("\(voyage.originPort ?? "Unknown") to \(voyage.destPort ?? "Unknown")")
                                .font(.callout)
                        } else {
                            Text("No voyage assessed")
                                .font(.callout)
                                .foregroundStyle(Theme.inkMuted)
                        }
                        DisclosureGroup("Risk factors and conditions") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(report.riskFactors, id: \.self) { Text($0) }
                                ForEach(report.warrantiesRequired, id: \.self) { Text($0) }
                            }
                            .font(.callout)
                            .padding(.top, 8)
                        }
                        if !report.retrievedGuidelines.isEmpty {
                            DisclosureGroup("Supporting guidelines") {
                                ForEach(report.retrievedGuidelines, id: \.self) { guideline in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(guideline.title).font(.caption.weight(.semibold))
                                        Text(guideline.excerpt).font(.caption)
                                    }
                                    .padding(.top, 8)
                                }
                            }
                        }
                    }
                } else {
                    Text("Assess this policy to see a risk score, premium recommendation and required conditions.")
                        .font(.callout)
                }
                if policy.stage == .draft || policy.stage == .quoted {
                    Button(policy.underwritingDecision == nil ? "Assess risk" : "Reassess risk", systemImage: "checkmark.shield") {
                        assessing = true
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.amber)
                    .accessibilityIdentifier("assess-risk")
                }
            }
        }
        .sheet(isPresented: $assessing) {
            UnderwritingSheet(policy: policy)
        }
    }
}

private struct UnderwritingSheet: View {
    let policy: Policy
    @Environment(Ledger.self) private var ledger
    @Environment(\.dismiss) private var dismiss
    @State private var vesselAge = 10
    @State private var voyageId: Int?
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Vessel age: \(vesselAge) years", value: $vesselAge, in: 0...100)
                        .accessibilityIdentifier("underwriting-vessel-age")
                    Picker("Voyage", selection: $voyageId) {
                        Text("No voyage assessment").tag(Int?.none)
                        ForEach(ledger.voyages.filter { $0.vesselId == policy.vesselId && policy.vesselId != nil }) { voyage in
                            Text("\(voyage.originPort ?? "Unknown") to \(voyage.destPort ?? "Unknown")")
                                .tag(Optional(voyage.id))
                        }
                    }
                    .accessibilityIdentifier("underwriting-voyage")
                } footer: {
                    Text("Enter the vessel's age and choose a voyage. Age is not stored on the vessel record. Route checks use local rules, not live AIS data.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(Theme.coral) }
                }
                Button {
                    Task { await assess() }
                } label: {
                    HStack {
                        if working { ProgressView() }
                        Text("Run assessment")
                    }
                }
                .disabled(working)
            }
            .navigationTitle("Assess policy #\(policy.policyNo)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(working)
                }
            }
            .onAppear {
                vesselAge = policy.underwritingReport?.vesselAge ?? 10
                voyageId = policy.underwritingReport?.voyageId
            }
        }
    }

    private func assess() async {
        working = true
        defer { working = false }
        do {
            let updated = try await APIClient.shared.assessPolicy(policy.policyNo, vesselAge: vesselAge, voyageId: voyageId)
            ledger.upsert(updated)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
