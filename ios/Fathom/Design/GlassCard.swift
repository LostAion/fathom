import SwiftUI

struct GlassCard<Content: View>: View {
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .glassEffect(tint.map { .regular.tint($0.opacity(0.25)) } ?? .regular, in: .rect(cornerRadius: 24))
    }
}

/// Title row plus scrolling content over the sonar background. Used by every tab.
struct Screen<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.rounded(.largeTitle, weight: .bold))
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkMuted)
                    }
                    Spacer()
                    ConnectionPill()
                }
                content
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .foregroundStyle(Theme.ink)
        .background { SonarBackground() }
    }
}
