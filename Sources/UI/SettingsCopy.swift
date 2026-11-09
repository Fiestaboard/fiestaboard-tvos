import Foundation

/// The A8 Settings copy (07b A8 `166:206997`, A8c–A8f), pinned by
/// `A8SettingsTests`. Phone-first: the phone app is where people change what
/// shows; the hub's web page is the fallback.
enum SettingsCopy {
    /// A8 `166:206997`.
    static let thisTVFooter = "Change what’s showing from the FiestaBoard app on your phone."
    /// A8e `269:131926`.
    static let aboutFooter = "Change what’s showing from the FiestaBoard app on your phone, or on your hub’s web page."
    /// DD17 / DD19: tvOS has no rows of its own here; it follows the system.
    /// 07b `290:139071`.
    static let accessibilityNote = "Follows your Apple TV’s Reduce Motion and Increase Contrast settings (Settings › Accessibility)."

    /// A8c `269:129632`: what the shared rows change, and the panel's night window.
    static func appearanceFooter(panelName: String, autoDim: AutoDim) -> String {
        let shared = "Shared: changes \(panelName) on every TV that shows it."
        guard autoDim.enabled else { return shared }
        return shared + " Night dimming schedule: \(Clock12.label(hhmm: autoDim.start)) – \(Clock12.label(hhmm: autoDim.end)), set on your phone or the hub."
    }

    /// A8d `269:131778`: the offline revoke goes through the phone.
    static func connectionFooter(deviceCredential: Bool, tvName: String) -> String {
        let lead = "Sign out keeps the hub address. Forget also removes it."
        guard deviceCredential else { return lead + " Nothing on the hub itself changes." }
        return lead + " Both erase this TV’s saved sign-in and revoke its access; if the hub is offline, revoke this TV on your phone in Displays › \(tvName) › Shown on."
    }

    /// A8f `277:138880`. The same for every sign-in: FiestaBot is retired (A9).
    static func privacyBody(tvName: String) -> String {
        "The app sends your requests to the hub you chose, at the address you typed or selected. "
            + "FiestaBoard’s servers and the app developer receive no analytics or tracking from this app. "
            + "The hub’s address and display preferences stay in this Apple TV’s app preferences; "
            + "a revocable TV credential is kept in its Keychain. Your password is sent to the hub only to sign in "
            + "and is not saved after a TV credential is issued; older hubs use a saved Keychain password to reconnect. "
            + "Sign out removes local credentials and asks the hub to revoke this TV; "
            + "if the hub is offline, revoke it on your phone in Displays › \(tvName) › Shown on."
    }

    static let privacyFooter = "The full privacy policy is linked from this app’s App Store page. Apple TV has no web browser, so it can’t be opened here."

    /// A8e's SCREEN PROTECTION caption (DD10).
    static let screenProtectionCaption = "This Apple TV stays awake while a board is showing. OLED care can dim, move and rest it; your TV may still dim or shift the picture for its own protection."

    /// About › Screen protection (DD10 + DD23).
    static let screenProtectionBody = """
        This Apple TV stays awake while a board is showing. OLED care, in Settings › This Apple TV, can lower \
        the brightness, move it a little, dim it at night, rest it on a schedule or when the hub can’t \
        be reached, and allow the Apple TV screen saver. Only Rest lets the TV sleep.

        OLED care reduces the risk of burn-in but can’t prevent it; your TV may still dim or shift the picture for its own protection.
        """

    static let topShelfBody = """
        Put FiestaBoard in the top row of the Home screen to see previews of your available panels. \
        Hold Select on the FiestaBoard icon, then move it into the top row. Open the app to refresh the \
        pictures. Select a preview to open that panel.
        """

    struct License: Equatable { let name: String; let text: String }

    /// The notices the app ships (A12): what each piece is and its terms
    /// (Resources/THIRD_PARTY_NOTICES.txt, which carries the owner's taco
    /// credit), then the full licence texts it refers to (Resources/OFL.txt,
    /// Resources/Matrix/LICENSE).
    static func licenses(bundle: Bundle = .main) -> [License] {
        func read(_ name: String, _ ext: String?) -> String {
            bundle.url(forResource: name, withExtension: ext).flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        }
        return [License(name: "Notices", text: read("THIRD_PARTY_NOTICES", "txt")),
                License(name: "Spline Sans Mono", text: read("OFL", "txt")),
                License(name: "MIT License", text: read("LICENSE", nil))]
    }
}

/// DD17 / DD19: the This Apple TV rows, in 07b's order.
enum SettingsLayout {
    enum Row: Equatable { case openAtLaunch, splitFlapSize, matrixSize, tvSize, ledSpacing, transitionStyle, oledCare, accessibilityNote }
    struct Section: Equatable { let title: String; let rows: [Row] }

    static func thisTV(matrixTrueSize: Bool) -> [Section] {
        [Section(title: "Playback", rows: [.openAtLaunch, .splitFlapSize]),
         Section(title: "LED matrix", rows: [.matrixSize] + (matrixTrueSize ? [.tvSize, .ledSpacing] : []) + [.transitionStyle]),
         Section(title: "Screen protection", rows: [.oledCare]),
         Section(title: "Accessibility", rows: [.accessibilityNote])]
    }

    /// DD20: legacy password sign-ins keep their only path to the night
    /// schedule and backdrop; device-code TVs match Android TV.
    static func showsAllDisplaySettings(usesDeviceCredential: Bool) -> Bool { !usesDeviceCredential }
}
