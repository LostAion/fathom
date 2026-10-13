import SwiftUI

/// Initials in a tinted ring, used as the avatar for people and organisations.
struct Monogram: View {
    let name: String
    let tint: Color
    var size: CGFloat = 44

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.16), in: .circle)
            .overlay(Circle().strokeBorder(tint.opacity(0.5), lineWidth: 1))
            .accessibilityHidden(true)
    }

    private var initials: String {
        name.split(separator: " ")
            .filter { $0.first?.isLetter == true }
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }
}

struct StatusChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: .capsule)
    }
}

struct SectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack {
            Text(title)
            if let count {
                Text("\(count)")
                    .foregroundStyle(Theme.inkMuted.opacity(0.7))
            }
        }
        .font(.caption.weight(.semibold))
        .textCase(.uppercase)
        .foregroundStyle(Theme.inkMuted)
        .padding(.top, 4)
    }
}

/// Shown while the first load is running or when it failed.
struct LedgerStatusCard: View {
    @Environment(Ledger.self) private var ledger

    var body: some View {
        if let error = ledger.loadError {
            GlassCard(tint: Theme.coral) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Couldn't load records", systemImage: "exclamationmark.triangle.fill")
                        .font(.rounded(.headline))
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(Theme.inkMuted)
                    Button("Try again") { Task { await ledger.refresh() } }
                        .buttonStyle(.glass)
                }
            }
        } else if !ledger.hasLoaded {
            GlassCard {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Sounding the records…")
                        .foregroundStyle(Theme.inkMuted)
                }
            }
        }
    }
}
