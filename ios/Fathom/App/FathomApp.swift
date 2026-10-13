import SwiftUI

@main
struct FathomApp: App {
    @State private var connection = ConnectionMonitor()
    @State private var ledger = Ledger()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(connection)
                .environment(ledger)
                .task {
                    await connection.check()
                    await ledger.refresh()
                }
        }
    }
}
