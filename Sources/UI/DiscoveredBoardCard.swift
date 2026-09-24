import SwiftUI

/// One FiestaBoard found on the network, shown the way tvOS shows content.
///
/// A discovered board is something you browse and pick, not a setting, so it
/// gets `CardButtonStyle`: the platform's lift, shadow and parallax tilt,
/// identical to every other card on the device. The brand is the amber glyph
/// and the focus accent, not a fill across the whole control.
struct DiscoveredBoardCard: View {
    let board: DiscoveredBoard
    /// Pre-computed so the card never has to know about its siblings.
    let address: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "rectangle.split.3x3.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Fiesta.Colors.brand)

                Spacer(minLength: 12)

                Text(board.name)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Fiesta.Colors.foreground)
                    .lineLimit(1)

                Text(address)
                    .font(.system(size: 24))
                    .foregroundStyle(Fiesta.Colors.mutedForeground)
                    .lineLimit(1)
            }
            .frame(width: 340, height: 190, alignment: .topLeading)
            .padding(28)
            .background(Fiesta.Colors.surface)
        }
        .buttonStyle(.card)
        .accessibilityLabel("\(board.name), \(address)")
        .accessibilityHint("Connects this Apple TV to this FiestaBoard.")
    }
}

/// How a discovered board's address is written under its name.
///
/// Two boards can live on the same host at different ports — a Pi running a
/// second instance does exactly that — so the hostname alone is not always a
/// label. The port is added only when it is what tells two rows apart, so the
/// common single-board case stays readable from the sofa.
enum BoardAddressLabel {

    static func text(for board: DiscoveredBoard, among boards: [DiscoveredBoard]) -> String {
        let host = hostname(of: board)
        let ambiguous = boards.contains { other in
            other.id != board.id && hostname(of: other) == host && other.host.port != board.host.port
        }
        guard ambiguous, let port = board.host.port else { return host }
        return "\(host):\(port)"
    }

    private static func hostname(of board: DiscoveredBoard) -> String {
        board.host.host() ?? board.host.absoluteString
    }
}
