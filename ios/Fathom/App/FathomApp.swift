import SwiftUI

@main
struct FathomApp: App {
    @State private var connection = ConnectionMonitor()
    @State private var ledger = Ledger()
    @State private var seaRoutes = SeaRoutes()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(connection)
                .environment(ledger)
                .environment(seaRoutes)
                .task {
                    await connection.check()
                    await ledger.refresh()
                }
        }
    }
}
