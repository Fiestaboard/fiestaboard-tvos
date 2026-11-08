import SwiftUI
import UIKit
import XCTest
@testable import FiestaBoardTV

/// A4a — the safe area (PHASE-4-TV-PLAN §2.2 A4a; 07b `tv/tvos/safe-side`
/// 80, `safe-top-bottom` 60).
///
/// The tvOS 4K simulator's root safe area is already 80/60, so screens use
/// it (no extra padding) and `PlatformTV` is applied explicitly only inside
/// the full-bleed viewer. Shots respect the safe area as the device does.
@MainActor
final class InsetTests: XCTestCase {

    override func setUp() {
        super.setUp()
        FigmaGeometryRegistry.shared.reset()
    }

    private func makeApp() -> AppModel {
        AppModel(connection: ConnectionStore(
            defaults: UserDefaults(suiteName: "tv.insets.\(UUID().uuidString)")!,
            credentials: InMemoryCredentialStore(),
            clientFactory: { FiestaClient(baseURL: $0, session: StubURLProtocol.makeSession()) }))
    }

    // MARK: The measurement the plan branches on

    func testTheRootSafeAreaIsTheSpecTitleSafe() throws {
        let window = UIWindow(frame: CGRect(origin: .zero, size: TVSnapshot.size))
        window.rootViewController = UIHostingController(rootView: Color.clear)
        window.isHidden = false
        defer { window.isHidden = true }
        XCTAssertEqual(window.safeAreaInsets,
                       UIEdgeInsets(top: PlatformTV.safeTopBottom, left: PlatformTV.safeSide,
                                    bottom: PlatformTV.safeTopBottom, right: PlatformTV.safeSide),
                       "80/60 on the 4K simulator: screens can use the system safe area")
    }

    // MARK: Headings at x = 80, y ≥ 60 on every screen

    private func assertHeadingAtTitleSafe(_ screen: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let eyebrow = try XCTUnwrap(FigmaGeometryRegistry.shared.snapshot()[FiestaScreenHeading.eyebrowProbe]?.frame,
                                    "\(screen): no heading", file: file, line: line)
        XCTAssertEqual(eyebrow.minX, PlatformTV.safeSide, accuracy: 1, "\(screen): eyebrow x", file: file, line: line)
        XCTAssertGreaterThanOrEqual(eyebrow.minY, PlatformTV.safeTopBottom - 0.5, "\(screen): eyebrow y", file: file, line: line)
        // 07b A1/A2/A3: the eyebrow sits at y 110 (title-safe 60 + 50).
        XCTAssertEqual(eyebrow.minY, 110, accuracy: 1, "\(screen): eyebrow at 07b's y 110", file: file, line: line)
    }

    func testConnectHeadingSitsAtTitleSafe() throws {
        _ = TVSnapshot.image(ConnectScreen().environment(makeApp()))
        try assertHeadingAtTitleSafe("Connect")
    }

    func testSignInHeadingSitsAtTitleSafe() throws {
        _ = TVSnapshot.image(SignInScreen().environment(makeApp()))
        try assertHeadingAtTitleSafe("Sign in")
    }

    func testDeviceSignInHeadingSitsAtTitleSafe() throws {
        _ = TVSnapshot.image(DeviceSignInScreen().environment(makeApp()))
        try assertHeadingAtTitleSafe("Device sign-in")
    }

    func testPanelsHeadingSitsAtTitleSafe() throws {
        _ = TVSnapshot.image(PanelsScreen().environment(makeApp()))
        try assertHeadingAtTitleSafe("Panels")
    }

    func testSettingsContentSitsAtTitleSafe() throws {
        _ = TVSnapshot.image(SettingsScreen().environment(makeApp()))
        let content = try XCTUnwrap(FigmaGeometryRegistry.shared.snapshot()[SettingsScreen.contentProbe]?.frame)
        XCTAssertEqual(content.minX, PlatformTV.safeSide, accuracy: 1, "Settings: categories x")
        XCTAssertEqual(content.maxX, TVSnapshot.size.width - PlatformTV.safeSide, accuracy: 1, "Settings: content ends at the safe edge")
    }

    // MARK: The full-bleed viewer applies PlatformTV itself

    /// A4 `I166:191865;149:182603;166:193875`: the overlay bar at (80, 60),
    /// 1760 wide.
    func testTheViewerOverlayBarIsTheA4Frame() throws {
        _ = TVSnapshot.image(ZStack {
            Color.black
            ViewerOverlay(panelName: "Living room TV", onInteraction: {}, onPanels: {}, onSettings: {}, onFiestaBot: nil)
        }, fullBleed: true)
        let bar = try XCTUnwrap(FigmaGeometryRegistry.shared.snapshot()[ViewerOverlay.barNode]?.frame)
        XCTAssertEqual(bar.minX, 80, accuracy: 1)
        XCTAssertEqual(bar.minY, 60, accuracy: 1)
        XCTAssertEqual(bar.width, 1760, accuracy: 1)
    }

    func testTheStatusPillSitsInsideTitleSafe() throws {
        _ = TVSnapshot.image(ZStack {
            Color.black
            BoardStatusPill(title: "Reconnecting", systemImage: "wifi.exclamationmark", tint: .orange, spoken: "x")
        }, fullBleed: true)
        let pill = try XCTUnwrap(FigmaGeometryRegistry.shared.snapshot()[BoardStatusPill.probe]?.frame)
        XCTAssertEqual(pill.maxX, TVSnapshot.size.width - PlatformTV.safeSide, accuracy: 1)
        XCTAssertEqual(pill.maxY, TVSnapshot.size.height - PlatformTV.safeTopBottom, accuracy: 1)
    }

    func testTheViewerMessageStaysInsideTitleSafe() throws {
        _ = TVSnapshot.image(ZStack {
            Color.black
            ViewerMessage(title: "This panel no longer exists",
                          detail: String(repeating: "A long explanation that wraps. ", count: 4),
                          primaryTitle: "Back to panels", primaryAction: {})
        }, fullBleed: true)
        let card = try XCTUnwrap(FigmaGeometryRegistry.shared.snapshot()[ViewerMessage.probe]?.frame)
        let safe = CGRect(origin: .zero, size: TVSnapshot.size)
            .insetBy(dx: PlatformTV.safeSide - 1, dy: PlatformTV.safeTopBottom - 1)
        XCTAssertTrue(safe.contains(card), "\(card) inside \(safe)")
    }

    // MARK: Shots respect the safe area

    func testShotsRespectTheSafeAreaUnlessFullBleed() throws {
        let probe = Color.clear.figmaNode("probe")
        _ = TVSnapshot.image(probe)
        let inset = try XCTUnwrap(FigmaGeometryRegistry.shared.snapshot()["probe"]?.frame)
        XCTAssertEqual(inset, CGRect(x: 80, y: 60, width: 1760, height: 960))
        FigmaGeometryRegistry.shared.reset()
        _ = TVSnapshot.image(probe, fullBleed: true)
        XCTAssertEqual(FigmaGeometryRegistry.shared.snapshot()["probe"]?.frame, CGRect(origin: .zero, size: TVSnapshot.size))
    }
}

/// #19 review nits 7.1 and 7.3.
final class A3NitTests: XCTestCase {

    /// The hub's pydantic `max_length` counts code points; a cap on grapheme
    /// clusters let multi-scalar emoji exceed it (a 422).
    func testTheNameCapCountsUnicodeScalarsAndNeverSplitsAGrapheme() {
        let family = "👨‍👩‍👧‍👦" // 7 scalars, 1 grapheme
        let name = DeviceName.sanitize(String(repeating: family, count: 60))
        XCTAssertLessThanOrEqual(name.unicodeScalars.count, 100)
        XCTAssertEqual(name.unicodeScalars.count % 7, 0, "whole emoji only")
        XCTAssertEqual(name.count, name.unicodeScalars.count / 7)
        XCTAssertEqual(DeviceName.sanitize(String(repeating: "a", count: 140)).unicodeScalars.count, 100)
    }

    /// Take focus for the phone path only if the user hasn't moved focus
    /// since the capability check started.
    func testThePhonePathTakesFocusOnlyIfFocusHasNotMoved() {
        XCTAssertTrue(SignInFocusPolicy.takePhonePath(enabled: true, focusAtCheck: nil, focusNow: nil))
        XCTAssertTrue(SignInFocusPolicy.takePhonePath(enabled: true, focusAtCheck: .username, focusNow: .username))
        XCTAssertFalse(SignInFocusPolicy.takePhonePath(enabled: true, focusAtCheck: .username, focusNow: .password),
                       "the user moved: leave them there")
        XCTAssertFalse(SignInFocusPolicy.takePhonePath(enabled: true, focusAtCheck: nil, focusNow: .submit))
        XCTAssertFalse(SignInFocusPolicy.takePhonePath(enabled: false, focusAtCheck: nil, focusNow: nil))
    }
}
