import Foundation

/// User-facing copy that 07b draws (PHASE-4-TV-PLAN A2). Each string bound
/// to a Figma text node names it, and `VocabularyTests` pins it to that
/// node's exact text, curly apostrophes and ellipses included.
///
/// Vocabulary (TV-APPS §4): the server is the **hub**; its name is the
/// Bonjour instance name until H13 PR 3 (DD8). The TV shows **panels**, which
/// are "your FiestaPanel displays". "Board" means only the picture.
enum TVCopy {

    /// A1 Connect, slot `I166:147296;149:182603`.
    enum Connect {
        static let eyebrow = "FiestaBoard"                                        // 166:147308
        static let title = "Find your FiestaBoard hub"                            // 166:147310
        static let subtitle = "Show your FiestaPanel displays on this TV. Choose the hub on your network to get started." // 166:147312
        /// Shown beside the found hubs while the scan keeps listening.
        static let stillLooking = "Still looking for other hubs on this network…" // 166:147342
        static let manualLabel = "Or enter your hub’s address"                    // 166:147344
        static let addressPlaceholder = "fiestapi.local or 192.168.1.20"          // 166:147348
        static let connect = "Connect"                                            // 166:147351

        /// Nothing found yet: no 07b frame; follows A1's family.
        static let looking = "Looking for FiestaBoard hubs on this network…"
        static let lookingDetail = "This takes a few seconds. Your hub needs to be powered on and on the same network as this Apple TV."
        static let foundNothing = "No FiestaBoard hub on this network yet"
        static let foundNothingDetail = "This Apple TV is still listening; a hub appears here within a few seconds of being powered on. If yours is on a different network, enter its address below."
        static let searchAgain = "Search again"

        /// DD8: the advertised Bonjour name, verbatim. Every hub advertises
        /// "FiestaBoard" until H13 PR 3; the host line tells them apart.
        static func hubCardTitle(for hub: DiscoveredBoard) -> String { hub.name }
        static func hubCardAccessibilityLabel(for hub: DiscoveredBoard, address: String,
                                              connecting: Bool = false) -> String {
            connecting ? "\(hub.name), \(address), connecting" : "\(hub.name), \(address)"
        }
        static let hubCardHint = "Connects this Apple TV to this hub."
        static let invalidAddress = "Enter an address like 192.168.1.20, fiestapi.local, or https://your-hub.example.com"
    }

    /// A2 Device sign-in, slot `I166:147391;149:182603`.
    enum DeviceSignIn {
        static let title = "Sign in with your phone"                              // 166:147405
        static let subtitle = "Scan the code with your phone’s camera, or open the address on any phone or computer on this network." // 166:147407
        static let retrySubtitle = "Choose New code to try again, or use your username and password."
        static let expiresPrefix = "Code expires in"                              // 166:147631
        static let waiting = "Waiting for approval on your phone…"               // 166:147645
        /// 166:147647 without its first sentence, "This TV will appear as …",
        /// which is the device name (A3, DD3).
        static let scope = "It can show your FiestaPanel displays and adjust how they look on this screen. It can’t change pages, messages or settings."
        /// A2 `166:147647` (user-assigned name) and DD3 fallback
        /// `249:110266`: the device-name sentence, then `scope`.
        static func scopeLine(for name: DeviceNameChoice) -> String {
            switch name {
            case .assigned(let name): return "This TV will appear as “\(name)”, its Apple TV name. " + scope
            case .fallback: return "This TV will appear as “\(DeviceName.fallback)”. " + scope
            }
        }
        /// After device-code approval (DD6; no 07b frame for the notice).
        static func approvedBy(_ username: String) -> String { "Approved by \(username)" }
        /// Not on the A2 frame yet: accepted as DD16 (the 07b designer draws it).
        static let reachability = "Your phone and this TV must both reach this hub. If the address won’t open, connect your phone to the same network."
        /// DD13: the activation address as A2 draws it
        /// (`fiestapi.local:4420/activate`). Drops only what a browser
        /// fills in itself — `http://`, `:80`, `:443` — and keeps any
        /// other port, which the person has to type. (DD12, which hides
        /// 4420 on the hub card, is a different rule for a label.)
        static func activationAddress(_ url: URL) -> String {
            guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return url.absoluteString
            }
            if parts.port == 80 || parts.port == 443 { parts.port = nil }
            var text = parts.string ?? url.absoluteString
            if text.hasPrefix("http://") { text.removeFirst("http://".count) }
            return text
        }

        static let newCode = "New code"
        static let usePassword = "Use username and password"
        static let back = "Back"
    }

    /// A3 Panels, slot `I166:147702;149:182603`.
    enum Panels {
        static let title = "Panels"                                               // 166:147716
        static let subtitle = "Your FiestaPanel displays. Choose one to show on this TV." // 166:147718
        /// Until the OLED-care invitation is dismissed (#13; A8 owns its frame).
        static let subtitleWithOLEDInvitation = "Your FiestaPanel displays. OLED TV? Optional setup in Settings → OLED care."
        static let settings = "Settings"                                          // 166:147721
    }

    enum Settings {
        static let connectedHeader = "Connected hub"
        static let forget = "Forget this hub"
        static let forgetConfirmTitle = "Forget this hub?"
    }

    enum SignIn {
        static let useAnother = "Use another hub"
    }

    enum Viewer {
        static let boardMissingTitle = "This panel’s virtual board was removed"
    }
}
