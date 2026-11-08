import SwiftUI
import XCTest
@testable import FiestaBoardTV

/// A2 — vocabulary and copy (PHASE-4-TV-PLAN §2.2 A2; TV-APPS §4 items 1, 2,
/// 4 and 7). The hub is a **hub**; "board" means only what is on screen.
///
/// Strings bound to a 07b text node are pinned here to that node's exact
/// text (curly apostrophes and ellipses included), so a copy edit has to
/// change the test and the frame together. The repo-wide hub-sense "board"
/// guard is `scripts/vocabulary/check-vocabulary.mjs`.
final class VocabularyTests: XCTestCase {

    // MARK: A1 Connect — I166:147296;149:182603

    func testConnectCopyIsTheA1Frame() {
        XCTAssertEqual(TVCopy.Connect.eyebrow, "FiestaBoard")                        // …;166:147308
        XCTAssertEqual(TVCopy.Connect.title, "Find your FiestaBoard hub")            // …;166:147310
        XCTAssertEqual(TVCopy.Connect.subtitle,                                      // …;166:147312
                       "Show your FiestaPanel displays on this TV. Choose the hub on your network to get started.")
        XCTAssertEqual(TVCopy.Connect.stillLooking, "Still looking for other hubs on this network…") // …;166:147342
        XCTAssertEqual(TVCopy.Connect.manualLabel, "Or enter your hub’s address")    // …;166:147344
        XCTAssertEqual(TVCopy.Connect.addressPlaceholder, "fiestapi.local or 192.168.1.20") // …;166:147348
        XCTAssertEqual(TVCopy.Connect.connect, "Connect")                            // …;166:147351
    }

    /// Scanning with nothing found yet has no 07b frame (review #16/#17 §5
    /// row 2); its copy follows A1's family.
    func testConnectScanningCopyFollowsTheA1Family() {
        XCTAssertEqual(TVCopy.Connect.looking, "Looking for FiestaBoard hubs on this network…")
        XCTAssertTrue(TVCopy.Connect.lookingDetail.contains("Your hub needs to be powered on"))
        XCTAssertEqual(TVCopy.Connect.foundNothing, "No FiestaBoard hub on this network yet")
    }

    /// DD8: until H13 PR 3, every hub advertises the Bonjour instance name
    /// "FiestaBoard". The card shows exactly what was advertised — the app
    /// never invents a friendlier name — over its host line.
    func testTheHubCardShowsTheAdvertisedNameVerbatim() {
        let hub = DiscoveredBoard(id: "http://192.168.1.20:4420", name: "FiestaBoard",
                                  host: URL(string: "http://192.168.1.20:4420")!)
        XCTAssertEqual(TVCopy.Connect.hubCardTitle(for: hub), "FiestaBoard")
        XCTAssertEqual(TVCopy.Connect.hubCardAccessibilityLabel(for: hub, address: "192.168.1.20:4420"),
                       "FiestaBoard, 192.168.1.20:4420")
        XCTAssertEqual(TVCopy.Connect.hubCardHint, "Connects this Apple TV to this hub.")
    }

    // MARK: A2 Device sign-in — I166:147391;149:182603

    func testDeviceSignInCopyIsTheA2Frame() {
        XCTAssertEqual(TVCopy.DeviceSignIn.title, "Sign in with your phone")         // …;166:147405
        XCTAssertEqual(TVCopy.DeviceSignIn.subtitle,                                 // …;166:147407
                       "Scan the code with your phone’s camera, or open the address on any phone or computer on this network.")
        XCTAssertEqual(TVCopy.DeviceSignIn.waiting, "Waiting for approval on your phone…") // …;166:147645
        XCTAssertEqual(TVCopy.DeviceSignIn.expiresPrefix, "Code expires in")         // …;166:147631
        XCTAssertEqual(TVCopy.DeviceSignIn.newCode, "New code")
        XCTAssertEqual(TVCopy.DeviceSignIn.usePassword, "Use username and password")
        XCTAssertEqual(TVCopy.DeviceSignIn.back, "Back")
    }

    /// The corrected scope line (TV-APPS §4 item 4): the old line claimed
    /// panels only and named FiestaBot. The device-name sentence in front of
    /// it ("This TV will appear as …", DD3) is A3's.
    func testTheScopeLineSaysWhatATVCredentialCanDo() {
        XCTAssertEqual(TVCopy.DeviceSignIn.scope,                                    // …;166:147647, minus A3's name sentence
                       "It can show your FiestaPanel displays and adjust how they look on this screen. It can’t change pages, messages or settings.")
    }

    func testThePendingPollReadsAsTheA2WaitingLine() {
        XCTAssertEqual(DevicePollError(code: "authorization_pending").userMessage, TVCopy.DeviceSignIn.waiting)
    }

    // MARK: A3 Panels — I166:147702;149:182603

    func testPanelsCopyIsTheA3Frame() {
        XCTAssertEqual(TVCopy.Panels.title, "Panels")                                // …;166:147716
        XCTAssertEqual(TVCopy.Panels.subtitle, "Your FiestaPanel displays. Choose one to show on this TV.") // …;166:147718
        XCTAssertEqual(TVCopy.Panels.settings, "Settings")                           // …;166:147721
    }

    // MARK: Hub sense, everywhere else

    func testSettingsNameTheHub() {
        XCTAssertEqual(TVCopy.Settings.connectedHeader, "Connected hub")
        XCTAssertEqual(TVCopy.Settings.forget, "Forget this hub")
        XCTAssertEqual(TVCopy.Settings.forgetConfirmTitle, "Forget this hub?")
        XCTAssertEqual(TVCopy.SignIn.useAnother, "Use another hub")
    }

    func testHubErrorsSayHub() {
        let messages = [
            DevicePollError(code: "slow_down").userMessage,
            DevicePollError(code: "feature_disabled").userMessage,
            DevicePollError(code: "session_limit").userMessage,
            DevicePollError(code: "something_else").userMessage,
            DeviceCredentialError.invalidResponse.userMessage,
        ]
        for message in messages {
            XCTAssertTrue(message.contains("hub"), message)
            XCTAssertFalse(message.range(of: #"\bboard\b"#, options: .regularExpression) != nil, message)
        }
    }

    // MARK: Viewer — web string family (TV-APPS §4 item 7)

    func testDisconnectedUsesTheWebString() {
        // web/messages/en.json → fiestaPanels.offline
        XCTAssertEqual(TVCopy.Viewer.disconnected, "Connection to FiestaBoard lost — showing the last update")
        XCTAssertEqual(TVCopy.Viewer.reconnecting, "Reconnecting")
    }

    /// "This panel's board was removed" read as the hub being gone
    /// (TV-APPS §4 item 1). It is the panel's virtual board.
    func testAMissingVirtualBoardSaysVirtualBoard() {
        XCTAssertEqual(TVCopy.Viewer.boardMissingTitle, "This panel’s virtual board was removed")
    }
}
