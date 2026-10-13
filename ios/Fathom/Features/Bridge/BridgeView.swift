import SwiftUI

/// Dashboard. For now it only reports the server connection; the charts come in a later step.
struct BridgeView: View {
    @Environment(ConnectionMonitor.self) private var connection

    var body: some View {
        Screen(title: "Bridge", subtitle: "Underwriting at a glance") {
            GlassCard(tint: tint) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Server")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                        .textCase(.uppercase)
                    switch connection.state {
                    case .checking:
                        Text("Sounding the line…")
                            .font(.rounded(.title2, weight: .semibold))
                    case .online(let database):
                        Text("Connected")
                            .font(.rounded(.title2, weight: .semibold))
                        Text(database)
                            .font(.callout.monospaced())
                            .foregroundStyle(Theme.inkMuted)
                    case .offline(let reason):
                        Text("No contact")
                            .font(.rounded(.title2, weight: .semibold))
                        Text(reason)
                            .font(.callout)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
            }
        }
        .refreshable { await connection.check() }
    }

    private var tint: Color {
        switch connection.state {
        case .checking: Theme.amber
        case .online: Theme.teal
        case .offline: Theme.coral
        }
    }
}
