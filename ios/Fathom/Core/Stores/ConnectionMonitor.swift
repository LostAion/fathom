import Foundation

@Observable
final class ConnectionMonitor {
    enum State: Equatable {
        case checking
        case online(database: String)
        case offline(reason: String)
    }

    private(set) var state = State.checking

    func check() async {
        state = .checking
        do {
            let health = try await APIClient.shared.health()
            state = .online(database: health.database)
        } catch {
            state = .offline(reason: error.localizedDescription)
        }
    }
}
