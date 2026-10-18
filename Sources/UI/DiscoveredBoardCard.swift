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
    /// Whether this is the board currently being connected to.
    var isConnecting = false
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
            // Inside the button's label, so the spinner lifts and tilts with
            // the card. An overlay outside `.buttonStyle(.card)` does not
            // take part in the card style's parallax and visibly detaches
            // from the plate the moment the card is focused.
            //
            // The card is never `.disabled` while this shows: on tvOS
            // disabling the focused control moves focus off it and it does
            // not reliably come back. The model's `guard !isConnecting` is
            // what stops a second attempt.
            .overlay(alignment: .bottomTrailing) {
                if isConnecting {
                    ProgressView()
                        .tint(Fiesta.Colors.brand)
                }
            }
            .padding(28)
            .background(Fiesta.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Fiesta.Metrics.cornerRadius))
            // A hairline, not a focus ring — it is there in every state, the
            // same as `PanelCard`. The plate is only a few luma values above
            // the app's near-black ground, so without an edge the card is a
            // floating glyph rather than a thing you can pick.
            .overlay(
                RoundedRectangle(cornerRadius: Fiesta.Metrics.cornerRadius)
                    .strokeBorder(Fiesta.Colors.border, lineWidth: 1))
        }
        .buttonStyle(.card)
        .accessibilityLabel(isConnecting ? "\(board.name), \(address), connecting" : "\(board.name), \(address)")
        .accessibilityHint("Connects this Apple TV to this FiestaBoard.")
    }
}

/// How a discovered board's address is written under its name.
///
/// Always in full, `host:port`. It used to be added only when two boards
/// shared a hostname, on the grounds that one board reads better without it
/// — but Bonjour will list anything that advertises itself convincingly, and
/// the address is the only thing on the card that tells a real board from
/// something else on the network wearing its name. A Pi running a second
/// instance on another port is a real deployment too, and it was the case
/// that motivated showing the port at all.
enum BoardAddressLabel {

    static func text(for board: DiscoveredBoard) -> String {
        let host = board.host.host() ?? board.host.absoluteString
        guard let port = board.host.port else { return host }
        return "\(host):\(port)"
    }
}
