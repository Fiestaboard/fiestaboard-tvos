import SwiftUI

extension TVCopy.Panels {
    // 07b A3 `166:149722` "Open at launch offer".
    static func openAtLaunchTitle(panel: String) -> String { "Always open \(panel)?" }   // 166:149723
    static func openAtLaunchBody(hub: String) -> String {                                // 166:149724
        "It’s the only panel on \(hub) that fits this TV. Open it straight away whenever the app starts. "
            + "You can change this in Settings › This Apple TV."
    }
    static let openAtLaunchAccept = "Always open"                                         // 166:149726
    static let openAtLaunchDismiss = "Not now"                                            // 166:149727
}

/// "Always open …?" in Panels' side slot (07b A3 `166:149722`): a card-fill
/// plate, radius 24, padding 40, gap 20; Headline, then Body in muted
/// foreground, then the two system buttons 24 apart.
struct OpenAtLaunchOfferCard: View {
    let panel: String
    let hub: String
    let accept: () -> Void
    let dismiss: () -> Void

    static let width: CGFloat = 800

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(TVCopy.Panels.openAtLaunchTitle(panel: panel))
                .font(Fiesta.Text.heading)
                .foregroundStyle(Fiesta.Colors.foreground)
                .lineLimit(2)
            Text(TVCopy.Panels.openAtLaunchBody(hub: hub))
                .font(Fiesta.Text.body)
                .foregroundStyle(Fiesta.Colors.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 24) {
                Button(TVCopy.Panels.openAtLaunchAccept, action: accept)
                Button(TVCopy.Panels.openAtLaunchDismiss, action: dismiss)
            }
            .font(Fiesta.Text.callout)
        }
        .padding(40)
        .frame(width: Self.width, alignment: .leading)
        .background(Fiesta.Colors.surface, in: RoundedRectangle(cornerRadius: PlatformTV.cardRadius))
        // Its own section: from the card column the remote moves right into
        // the buttons, not past them.
        .focusSection()
    }
}
