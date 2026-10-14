import SwiftUI

struct FlowStep {
    /// Short name, used for accessibility ("Client").
    let title: String
    /// The question shown at the top of the step ("Who is being insured?").
    let prompt: String
    /// Next stays disabled until this is true.
    var isComplete = true
}

/// Full-screen, one-question-at-a-time creation flow used instead of long forms
/// (Issue Policy, Plot Voyage, File Claim). Present it with `.fullScreenCover` or `.sheet`.
struct GuidedFlow<Content: View>: View {
    let title: String
    let tint: Color
    let steps: [FlowStep]
    let finishLabel: String
    let onFinish: () async throws -> Void
    let content: (Int) -> Content

    @State private var current = 0
    @State private var forward = true
    @State private var busy = false
    @State private var error: String?
    @State private var advances = 0
    @State private var finishes = 0
    @Environment(\.dismiss) private var dismiss

    init(title: String, tint: Color, steps: [FlowStep], finishLabel: String,
         onFinish: @escaping () async throws -> Void,
         @ViewBuilder content: @escaping (_ step: Int) -> Content) {
        self.title = title
        self.tint = tint
        self.steps = steps
        self.finishLabel = finishLabel
        self.onFinish = onFinish
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            progress
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(steps[current].prompt)
                        .font(.rounded(.title, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    content(current)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(current)
                .transition(.asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .opacity
                ))
            }
            .scrollDismissesKeyboard(.interactively)
            bottomBar
        }
        .foregroundStyle(Theme.ink)
        .background { SonarBackground() }
        .interactiveDismissDisabled(current > 0)
        .sensoryFeedback(.impact(weight: .light), trigger: advances)
        .sensoryFeedback(.success, trigger: finishes)
    }

    private var isLast: Bool { current == steps.count - 1 }

    private var topBar: some View {
        HStack {
            Button("Close", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.headline)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
            Spacer()
            VStack(spacing: 2) {
                Text(title)
                    .font(.rounded(.headline))
                Text("Step \(current + 1) of \(steps.count)")
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .contentTransition(.numericText())
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(steps.indices, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? tint : Theme.inkMuted.opacity(0.25))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(steps.count): \(steps[current].title)")
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Theme.coral)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
                if current > 0 {
                    Button("Back") { move(by: -1) }
                        .buttonStyle(.glass)
                        .disabled(busy)
                }
                Button {
                    if isLast { Task { await finish() } } else { move(by: 1) }
                } label: {
                    HStack {
                        if busy { ProgressView() }
                        Text(isLast ? finishLabel : "Next")
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(tint)
                .disabled(!steps[current].isComplete || busy)
            }
            .font(.rounded(.headline))
            .controlSize(.large)
        }
        .padding(20)
    }

    private func move(by offset: Int) {
        error = nil
        forward = offset > 0
        withAnimation(.snappy) { current += offset }
        if offset > 0 { advances += 1 }
    }

    private func finish() async {
        busy = true
        defer { busy = false }
        do {
            try await onFinish()
            finishes += 1
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
