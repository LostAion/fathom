import SwiftUI

@main
struct FathomApp: App {
    @State private var connection = ConnectionMonitor()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(connection)
                .task { await connection.check() }
        }
    }
}
