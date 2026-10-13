import Foundation

/// Local copy of every table. The data set is small, so the app loads it all
/// up front and screens filter and join it locally instead of calling the API per view.
@Observable
final class Ledger {
    private static let tables: [any APIModel.Type] = [
        Client.self, Broker.self, Surveyor.self, Reinsurer.self, Cargo.self, Vessel.self,
        Department.self, Underwriter.self, Voyage.self, Policy.self, Claim.self,
        ReinsuredBy.self, AssessedBy.self, Carries.self,
    ]

    private var rows: [String: [any APIModel]] = [:]
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var loadError: String?

    func all<T: APIModel>(_ type: T.Type) -> [T] {
        rows[T.collection] as? [T] ?? []
    }

    var clients: [Client] { all(Client.self) }
    var brokers: [Broker] { all(Broker.self) }
    var surveyors: [Surveyor] { all(Surveyor.self) }
    var reinsurers: [Reinsurer] { all(Reinsurer.self) }
    var cargos: [Cargo] { all(Cargo.self) }
    var vessels: [Vessel] { all(Vessel.self) }
    var departments: [Department] { all(Department.self) }
    var underwriters: [Underwriter] { all(Underwriter.self) }
    var voyages: [Voyage] { all(Voyage.self) }
    var policies: [Policy] { all(Policy.self) }
    var claims: [Claim] { all(Claim.self) }
    var reinsuredBy: [ReinsuredBy] { all(ReinsuredBy.self) }
    var assessedBy: [AssessedBy] { all(AssessedBy.self) }
    var carries: [Carries] { all(Carries.self) }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            for table in Self.tables {
                try await load(table)
            }
            hasLoaded = true
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    @discardableResult
    func save<T: APIModel>(_ item: T, isNew: Bool) async throws -> T {
        let saved = isNew ? try await APIClient.shared.create(item) : try await APIClient.shared.update(item)
        upsert(saved)
        return saved
    }

    /// Stores a row the server returned, e.g. from `policies/{no}/bind` or `claims/{id}/settle`.
    func upsert<T: APIModel>(_ item: T) {
        var list = all(T.self)
        if let index = list.firstIndex(where: { $0.id == item.id }) {
            list[index] = item
        } else {
            list.append(item)
        }
        rows[T.collection] = list
    }

    /// Deletes cascade or null out foreign keys on the server, so reload everything afterwards.
    func delete<T: APIModel>(_ item: T) async throws {
        try await APIClient.shared.delete(item)
        rows[T.collection] = all(T.self).filter { $0.id != item.id }
        await refresh()
    }

    private func load<T: APIModel>(_ type: T.Type) async throws {
        rows[T.collection] = try await APIClient.shared.list(type)
    }
}
