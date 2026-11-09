import SwiftUI
import XCTest
@testable import FiestaBoardTV

/// A8 (4.4): Settings rows, screen care and states. DD17, DD19, DD20, DD21,
/// DD23 and the 07b copy follow-ups (A8 `166:206997`, A8b `248:110205`,
/// A8b·1 `279:139039`, A8c `269:129632`, A8d `269:131778`, A8e `269:131926`,
/// A8f `277:138880`).
final class A8SettingsTests: XCTestCase {

    // MARK: DD21 LED spacing

    /// The `Int(pitch)` bug read a hub value of 2.5 as "2 mm".
    func testLEDSpacingPrintsItsShortestExactForm() {
        XCTAssertEqual(LEDSpacing.label(2.5), "2.5 mm")
        XCTAssertEqual(LEDSpacing.label(6), "6 mm")
        XCTAssertEqual(LEDSpacing.label(6.0), "6 mm")
        XCTAssertEqual(LEDSpacing.label(12), "12 mm")
        XCTAssertEqual(LEDSpacing.presets, [1, 2, 2.5, 3, 4, 5, 6, 8, 10, 12, 16, 20], "the same presets as Android TV")
    }

    // MARK: DD17 / DD19 This Apple TV

    func testThisAppleTVHasFourLabelledSections() {
        let sections = SettingsLayout.thisTV(matrixTrueSize: true)
        XCTAssertEqual(sections.map(\.title), ["Playback", "LED matrix", "Screen protection", "Accessibility"])
        XCTAssertEqual(sections[0].rows, [.openAtLaunch, .splitFlapSize])
        XCTAssertEqual(sections[1].rows, [.matrixSize, .tvSize, .ledSpacing, .transitionStyle],
                       "A8 166:206997: TV size and LED spacing sit under Matrix size")
        XCTAssertEqual(sections[2].rows, [.oledCare], "night dimming and drift live in OLED care (DD17)")
        XCTAssertEqual(sections[3].rows, [.accessibilityNote], "tvOS follows the system settings; no row of its own (DD19)")
    }

    func testTVSizeAndLEDSpacingOnlyForTrueLEDSize() {
        XCTAssertEqual(SettingsLayout.thisTV(matrixTrueSize: false)[1].rows, [.matrixSize, .transitionStyle])
    }

    /// DD20: legacy password sign-ins keep their only path to the night schedule and backdrop.
    func testAllDisplaySettingsOnlyForLegacySignIns() {
        XCTAssertTrue(SettingsLayout.showsAllDisplaySettings(usesDeviceCredential: false))
        XCTAssertFalse(SettingsLayout.showsAllDisplaySettings(usesDeviceCredential: true))
    }

    // MARK: Copy

    /// 07b `290:139071`: the Accessibility note, word for word.
    func testTheAccessibilityNoteIsThe07bText() {
        XCTAssertEqual(SettingsCopy.accessibilityNote,
                       "Follows your Apple TV’s Reduce Motion and Increase Contrast settings (Settings › Accessibility).")
    }

    /// A8d / DD13: the hub address drops what a browser fills in itself
    /// (`http://`, :80, :443) and keeps any other port, as Android's
    /// `hubDisplayAddress` and the activation address do.
    func testTheHubAddressUsesTheDD13DisplayRule() {
        XCTAssertEqual(TVCopy.displayAddress(URL(string: "http://fiestapi.local:4420")!), "fiestapi.local:4420")
        XCTAssertEqual(TVCopy.displayAddress(URL(string: "http://fiestapi.local:80")!), "fiestapi.local")
        XCTAssertEqual(TVCopy.displayAddress(URL(string: "http://192.168.1.30:4420")!), "192.168.1.30:4420")
        XCTAssertEqual(TVCopy.displayAddress(URL(string: "https://hub.example.com:443")!), "https://hub.example.com",
                       "https stays visible: it is not what a browser assumes")
        XCTAssertEqual(TVCopy.DeviceSignIn.activationAddress(URL(string: "http://fiestapi.local:4420/activate")!),
                       "fiestapi.local:4420/activate", "the activation address keeps the same rule")
    }

    func testPhoneFirstFooters() {
        XCTAssertEqual(SettingsCopy.thisTVFooter, "Change what’s showing from the FiestaBoard app on your phone.")
        XCTAssertEqual(SettingsCopy.aboutFooter, "Change what’s showing from the FiestaBoard app on your phone, or on your hub’s web page.")
    }

    /// A8c: the shared footer names the panel and its dimming window in 12-hour time.
    func testTheAppearanceFooterSaysWhatIsShared() {
        XCTAssertEqual(SettingsCopy.appearanceFooter(panelName: "Living room TV", autoDim: AutoDim(enabled: true, start: "22:00", end: "07:00")),
                       "Shared: changes Living room TV on every TV that shows it. Night dimming schedule: 10:00 PM – 7:00 AM, set on your phone or the hub.")
        XCTAssertEqual(SettingsCopy.appearanceFooter(panelName: "Lobby", autoDim: AutoDim(enabled: false)),
                       "Shared: changes Lobby on every TV that shows it.")
    }

    /// A8d: the offline revoke points to the phone.
    func testTheConnectionFooterPointsToThePhone() {
        XCTAssertEqual(SettingsCopy.connectionFooter(deviceCredential: true, tvName: "Living room TV"),
                       "Sign out keeps the hub address. Forget also removes it. Both erase this TV’s saved sign-in and revoke its access; if the hub is offline, revoke this TV on your phone in Displays › Living room TV › Shown on.")
        XCTAssertEqual(SettingsCopy.connectionFooter(deviceCredential: false, tvName: "Living room TV"),
                       "Sign out keeps the hub address. Forget also removes it. Nothing on the hub itself changes.")
    }

    /// A8f: no FiestaBot, AI-provider or Siri lines; the revoke goes through the phone.
    func testPrivacyIsTheA8fText() {
        let body = SettingsCopy.privacyBody(tvName: "Living room TV")
        XCTAssertTrue(body.hasPrefix("The app sends your requests to the hub you chose, at the address you typed or selected."))
        XCTAssertTrue(body.contains("FiestaBoard’s servers and the app developer receive no analytics or tracking from this app."))
        XCTAssertTrue(body.contains("Your password is sent to the hub only to sign in"))
        XCTAssertTrue(body.hasSuffix("if the hub is offline, revoke it on your phone in Displays › Living room TV › Shown on."))
        for gone in ["FiestaBot", "AI provider", "Siri", "local network", "may share"] {
            XCTAssertFalse(body.contains(gone), gone)
        }
        XCTAssertEqual(SettingsCopy.privacyFooter,
                       "The full privacy policy is linked from this app’s App Store page. Apple TV has no web browser, so it can’t be opened here.")
    }

    /// A9 (the #26 must-fix carried forward): FiestaBot is retired, so the
    /// legacy-sign-in branch is gone. Every TV reads the same A8f text, and
    /// SettingsCopy has no FiestaBot, AI-provider or Siri disclosure left.
    func testPrivacyHasNoFiestaBotBranchAfterA9() throws {
        let body = SettingsCopy.privacyBody(tvName: "Living room TV")
        for gone in ["FiestaBot", "AI provider", "Siri", "Chat history"] { XCTAssertFalse(body.contains(gone), gone) }
        let source = try String(contentsOf: TVSnapshot.repoRoot
            .appendingPathComponent("Sources/UI/SettingsCopy.swift"), encoding: .utf8)
        for gone in ["fiestaBotDisclosure", "legacySignIn", "AI provider"] { XCTAssertFalse(source.contains(gone), gone) }
    }

    /// DD10 + DD23: what the TV does, and the one honest burn-in sentence.
    func testScreenProtectionCarriesTheDD23Sentence() {
        XCTAssertEqual(SettingsCopy.screenProtectionCaption,
                       "This Apple TV stays awake while a board is showing. OLED care can dim, move and rest it; your TV may still dim or shift the picture for its own protection.")
        XCTAssertTrue(SettingsCopy.screenProtectionBody.contains(
            "OLED care reduces the risk of burn-in but can’t prevent it; your TV may still dim or shift the picture for its own protection."))
    }

    func testLicensesListTheBundledNotices() throws {
        let entries = SettingsCopy.licenses(bundle: Bundle(for: AppModel.self))
        // A12 put the notices first (A12ReleaseReadinessTests pins them).
        XCTAssertEqual(entries.map(\.name), ["Notices", "Spline Sans Mono", "MIT License"])
        for entry in entries { XCTAssertGreaterThan(entry.text.count, 200, "\(entry.name) ships its full notice") }
        XCTAssertTrue(entries[1].text.contains("SIL OPEN FONT LICENSE"))
    }

    /// The deleted-panel state (plan row A8: "This display was removed on your hub").
    func testTheDeletedPanelState() {
        XCTAssertEqual(TVCopy.Viewer.deletedTitle, "This display was removed on your hub")
    }

    // MARK: DD17 OLED care summary (A8b)


    func testTwelveHourTimes() {
        XCTAssertEqual(Clock12.label(minutes: 22 * 60), "10:00 PM")
        XCTAssertEqual(Clock12.label(minutes: 7 * 60), "7:00 AM")
        XCTAssertEqual(Clock12.label(minutes: 0), "12:00 AM")
        XCTAssertEqual(Clock12.label(minutes: 12 * 60 + 5), "12:05 PM")
    }

    func testTheOLEDCareRowsSummariseEachChoice() {
        var c = OLEDCareConfiguration()
        c.brightness = 80; c.movement = true; c.movementRange = 8
        c.restEnabled = true; c.restStart = 22 * 60; c.restEnd = 7 * 60
        c.rotationEnabled = true; c.disconnected = .dim; c.disconnectDelay = 5
        let s = OLEDCareSummary(c, neverDim: false)
        XCTAssertEqual(s.brightness, "80 %")
        XCTAssertEqual(s.movement, "Gentle")
        XCTAssertEqual(s.night, "Follow panel", "07b G9 wording, the same as Android TV")
        XCTAssertEqual(s.rest, "10:00 PM – 7:00 AM")
        XCTAssertEqual(s.breaks, "Off")
        XCTAssertEqual(s.rotation, "On")
        XCTAssertEqual(s.disconnected, "Dim after 5 min")
        XCTAssertEqual(s.screensaver, "Off")
        c.movementRange = 24; c.breaksEnabled = true; c.breakInterval = 60; c.nightMode = .custom; c.disconnected = .keep
        let t = OLEDCareSummary(c, neverDim: false)
        XCTAssertEqual(t.movement, "Wider")
        XCTAssertEqual(t.breaks, "Every 60 min")
        XCTAssertEqual(t.night, "Custom")
        c.nightMode = .never
        XCTAssertEqual(OLEDCareSummary(c, neverDim: false).night, "Never")
        XCTAssertEqual(t.disconnected, "Keep last frame")
    }

    /// DD17: "On", or "Off" only when every care option is off (Android's `OledCare.isOn`).
    func testTheOLEDCareRowIsOffOnlyWhenEverythingIsOff() {
        var c = OLEDCareConfiguration()
        c.nightMode = .never
        XCTAssertFalse(OLEDCareSummary(c, neverDim: false).isOn)
        XCTAssertEqual(OLEDCareSummary(c, neverDim: false).rowValue, "Off")
        c.nightMode = .followPanel
        XCTAssertTrue(OLEDCareSummary(c, neverDim: false).isOn, "following the panel's night dimming is care")
        XCTAssertFalse(OLEDCareSummary(c, neverDim: true).isOn, "unless this TV never dims")
        XCTAssertEqual(OLEDCareSummary(c, neverDim: false).rowValue, "On · only this Apple TV")
        for change: (inout OLEDCareConfiguration) -> Void in [
            { $0.brightness = 75 }, { $0.movement = true }, { $0.restEnabled = true }, { $0.breaksEnabled = true },
            { $0.rotationEnabled = true }, { $0.disconnected = .rest },
        ] {
            var d = OLEDCareConfiguration(); d.nightMode = .never; change(&d)
            XCTAssertTrue(OLEDCareSummary(d, neverDim: false).isOn)
        }
    }

    // MARK: DD19 Increase Contrast

    func testIncreaseContrastDropsTheLensLighting() {
        XCTAssertTrue(MatrixCanvas.lensLighting(reduceTransparency: false, contrast: .standard))
        XCTAssertFalse(MatrixCanvas.lensLighting(reduceTransparency: false, contrast: .increased))
        XCTAssertFalse(MatrixCanvas.lensLighting(reduceTransparency: true, contrast: .standard))
    }
}
