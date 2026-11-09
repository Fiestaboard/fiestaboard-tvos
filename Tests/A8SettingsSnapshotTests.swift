import SwiftUI
import UIKit
import XCTest
@testable import FiestaBoardTV

/// A8 goldens (precision 1.0). Offscreen, so nothing is focused; the focus
/// platter is XCUITest's (`SettingsPresentationTests`).
///
/// Golden ↔ 07b:
/// - `settings-this-tv-true-led` → A8 `166:206997` (True LED state)
/// - `settings-panel-appearance` → A8c `269:129632`
/// - `settings-connection` → A8d `269:131778`
/// - `settings-about` → A8e `269:131926`
/// - `settings-privacy` → A8f `277:138880`
/// - `settings-oled-care` → A8b `248:110205`
/// - `settings-night-dimming` → A8b·1 `279:139039`
@MainActor
final class A8SettingsSnapshotTests: XCTestCase {

    override func setUp() { super.setUp(); StubURLProtocol.reset(); FigmaGeometryRegistry.shared.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    private func signage(trueSize: Bool) -> SignageSettings {
        let settings = SignageSettings(defaults: UserDefaults(suiteName: "a8.\(UUID().uuidString)")!)
        if trueSize { settings.matrixPresentation = MatrixPresentation(sizing: .trueSize, diagonalInches: 55, pitchMillimeters: 6) }
        return settings
    }

    private func app(oled: OLEDCareConfiguration? = nil) async -> AppModel {
        let app = AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "a8.app.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) }),
            // Its own store: OLED care saved here must not reach other tests' viewers.
            oledStore: OLEDCareStore(defaults: UserDefaults(suiteName: "a8.oled.\(UUID().uuidString)")!),
            deviceName: .assigned("Living room TV"))
        StubURLProtocol.enqueue(.json(Fixtures.authStatusDisabled), for: "/api/auth/status")
        _ = try? await app.connection.connect(to: URL(string: "http://fiestapi.local:4420")!, displayName: "Maya’s FiestaPi")
        if let oled { app.saveOLEDCare(oled) }
        // N1: a render style, so A8c's Display style row is in the golden.
        let panel = String(Fixtures.panelJSON.dropLast()) + #","render_style":"split_flap"}"#
        StubURLProtocol.enqueue(.json(#"{"panels":["# + panel + #"],"total":1}"#), for: "/api/panels")
        for _ in 0..<4 { StubURLProtocol.enqueue(.json(Fixtures.frameJSON), for: "/frame") }
        return app
    }

    /// Rendered from a loaded model, so no golden can catch "Loading panels…".
    private func settings(_ category: SettingsScreen.Category, trueSize: Bool = false) async -> UIImage {
        let app = await app()
        let signage = signage(trueSize: trueSize)
        let model = SettingsModel(app: app, signage: signage)
        await model.load()
        if let panel = model.panels.first { await model.loadPreview(for: panel) }
        XCTAssertFalse(model.panels.isEmpty, "the golden shows a loaded panel list")
        return TVSnapshot.image(SettingsScreen(initialCategory: category, signage: signage, model: model).environment(app), settle: 1.0)
    }

    func testThisAppleTVInTheTrueLEDState() async {
        TVSnapshot.assertMatches(await settings(.tv, trueSize: true), named: "settings-this-tv-true-led")
    }

    func testPanelAppearance() async {
        TVSnapshot.assertMatches(await settings(.appearance), named: "settings-panel-appearance")
    }

    func testConnection() async {
        TVSnapshot.assertMatches(await settings(.connection), named: "settings-connection")
    }

    func testAboutAndHelp() async {
        TVSnapshot.assertMatches(await settings(.help), named: "settings-about")
    }

    /// A8f: the body is one scroll target; title Title 3 48, body 29, footer 23.
    func testThePrivacyDetailPage() async {
        let image = TVSnapshot.image(SettingsDetailPage(title: "Privacy", body: SettingsCopy.privacyBody(tvName: "Living room TV"),
                                                        footer: SettingsCopy.privacyFooter)
            .frame(width: 1200, height: 860, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing), settle: 0.3)
        TVSnapshot.assertMatches(image, named: "settings-privacy")
    }

    func testOLEDCare() async {
        var c = OLEDCareConfiguration()
        c.brightness = 75; c.movement = true; c.rotationEnabled = true
        c.restEnabled = true; c.restStart = 22 * 60; c.restEnd = 7 * 60
        c.disconnected = .dim
        let app = await app(oled: c)
        TVSnapshot.assertMatches(TVSnapshot.image(NavigationStack { OLEDCareScreen() }.environment(app), settle: 0.5),
                                 named: "settings-oled-care")
    }

    func testNightDimming() async {
        var c = OLEDCareConfiguration()
        c.nightMode = .custom
        let app = await app(oled: c)
        TVSnapshot.assertMatches(TVSnapshot.image(NavigationStack { NightDimmingScreen() }.environment(app), settle: 0.5),
                                 named: "settings-night-dimming")
    }
}
