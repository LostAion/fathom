import SwiftUI

/// A voyage row that links to its detail and charts its route if needed.
struct VoyageLink: View {
    let voyage: Voyage
    @Environment(SeaRoutes.self) private var seaRoutes

    var body: some View {
        let plot = VoyagePlot.make(voyage, seaRoutes: seaRoutes, now: .now)
        NavigationLink(value: AppRoute.voyage(voyage.id)) {
            VoyageRow(voyage: voyage,
                      distance: plot.flatMap { $0.track.isSeaLane ? $0.track.distanceText : nil },
                      state: plot?.state ?? VoyageState.classify(depart: voyage.departs, hoursAtSea: nil, now: .now))
        }
        .buttonStyle(.plain)
        .task { _ = await seaRoutes.chart(voyage) }
    }
}

/// Edit and Delete toolbar buttons with a confirmation that says what the foreign keys will do.
private struct RecordActions: ViewModifier {
    let available: Bool
    let name: String
    let deleteLabel: String
    let effect: String
    @Binding var editing: Bool
    let delete: () async throws -> Void

    @State private var confirming = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .toolbar {
                if available {
                    ToolbarItem {
                        Button("Edit") { editing = true }
                    }
                    ToolbarItem {
                        Button("Delete", systemImage: "trash", role: .destructive) { confirming = true }
                    }
                }
            }
            .confirmationDialog("Delete \(name)?", isPresented: $confirming, titleVisibility: .visible) {
                Button(deleteLabel, role: .destructive) {
                    Task {
                        do {
                            try await delete()
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
            } message: {
                Text(effect)
            }
            .alert("Couldn't delete", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: {
                Text(error ?? "")
            }
    }
}

extension View {
    /// `available` is false once the record is gone; the modifier stays attached so the delete can finish.
    func recordActions(available: Bool, name: String, deleteLabel: String, effect: String, editing: Binding<Bool>,
                       delete: @escaping () async throws -> Void) -> some View {
        modifier(RecordActions(available: available, name: name, deleteLabel: deleteLabel, effect: effect,
                               editing: editing, delete: delete))
    }
}

/// Scrolling page over the sonar background, shared by the Fleet detail screens.
struct DetailPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .foregroundStyle(Theme.ink)
        .background { SonarBackground() }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// "None yet" line under an empty section.
struct NoneYet: View {
    var text = "None yet"

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(Theme.inkMuted)
    }
}

/// What SET NULL does to rows that point at a deleted record.
func unlinkNote(_ count: Int, _ singular: String, _ plural: String, losing: String) -> String? {
    count == 0 ? nil : "\(counted(count, singular, plural)) will stay on file but lose this \(losing) (ON DELETE SET NULL)."
}
