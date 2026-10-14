import SwiftUI

/// "Add a new …" row at the end of a picker, so a flow never dead-ends on an empty list.
struct AddNewButton: View {
    let title: String
    var tint: Color = Theme.teal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus.circle.fill")
                .font(.rounded(.headline))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(tint.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
