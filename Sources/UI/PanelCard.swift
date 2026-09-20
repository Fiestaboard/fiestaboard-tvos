import SwiftUI

struct PanelCard: View {
    let panel: Panel
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(panel.name)
                    .font(Fiesta.Text.heading)
                    .lineLimit(1)
                HStack(spacing: 16) {
                    Text(panel.gridDescription)
                    Text("·")
                    Text(panel.screenDescription)
                }
                .font(Fiesta.Text.caption)
                .foregroundStyle(Fiesta.Colors.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .buttonStyle(.plain)
        .background(focused ? Fiesta.Colors.surfaceRaised : Fiesta.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Fiesta.Metrics.cornerRadius)
                .stroke(focused ? Fiesta.Colors.brand : Fiesta.Colors.border, lineWidth: focused ? 4 : 1))
        .clipShape(RoundedRectangle(cornerRadius: Fiesta.Metrics.cornerRadius))
        .focused($focused)
        .scaleEffect(focused ? 1.03 : 1.0)
        .animation(.easeOut(duration: 0.15), value: focused)
        .disabled(panel.boardMissing)
        .opacity(panel.boardMissing ? 0.5 : 1)
    }
}
