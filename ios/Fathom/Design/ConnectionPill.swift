import SwiftUI

/// Shows whether the API is reachable. Tap to change the server address
/// (needed when running on a physical iPhone against a Mac on the same Wi-Fi).
struct ConnectionPill: View {
    @Environment(ConnectionMonitor.self) private var connection
    @State private var showingServer = false

    var body: some View {
        Button { showingServer = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(color)
                    .symbolEffect(.pulse, isActive: connection.state == .checking)
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(color.opacity(0.2)).interactive(), in: .capsule)
        .accessibilityLabel("Server status: \(label)")
        .sheet(isPresented: $showingServer) {
            ServerSheet()
                .presentationDetents([.medium])
        }
    }

    private var label: String {
        switch connection.state {
        case .checking: "Sounding…"
        case .online: "Connected"
        case .offline: "Offline"
        }
    }

    private var color: Color {
        switch connection.state {
        case .checking: Theme.amber
        case .online: Theme.teal
        case .offline: Theme.coral
        }
    }
}

private struct ServerSheet: View {
    @Environment(ConnectionMonitor.self) private var connection
    @Environment(Ledger.self) private var ledger
    @Environment(\.dismiss) private var dismiss
    @AppStorage(APIClient.baseURLKey) private var baseURL = APIClient.defaultBaseURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                } header: {
                    Text("API address")
                } footer: {
                    Text("Simulator: \(APIClient.defaultBaseURL)\nPhysical iPhone: http://<your Mac's IP>:8000/api")
                }

                Section("Status") {
                    switch connection.state {
                    case .checking:
                        Label("Checking…", systemImage: "dot.radiowaves.left.and.right")
                    case .online(let database):
                        Label("Connected to \(database)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.teal)
                    case .offline(let reason):
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.coral)
                    }
                }
            }
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { baseURL = APIClient.defaultBaseURL }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        Task {
                            await connection.check()
                            if case .online = connection.state {
                                dismiss()
                                await ledger.refresh()
                            }
                        }
                    }
                }
            }
        }
    }
}
