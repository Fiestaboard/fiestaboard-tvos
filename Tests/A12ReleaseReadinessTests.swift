import XCTest
@testable import FiestaBoardTV

/// A12 — release readiness that needs no Apple TV (PHASE-4-TV-PLAN §2.2 A12;
/// the Android twin is androidtv #29's LicenseNoticesTest and
/// ReleaseReadinessTest). Every check reads the real repo files or the built
/// app bundle, never a copy.
final class A12ReleaseReadinessTests: XCTestCase {

    private static let root = TVSnapshot.repoRoot

    private static func text(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private static var appBundle: Bundle { Bundle(for: AppModel.self) }

    // MARK: Licence notices

    /// The owner's ruling (2026-11-08): the taco art is not MIT.
    static let tacoCredit = "Taco artwork © FiestaBoard. All rights reserved. Used in this app with permission."

    func testTheNoticesCreditEveryBundledFontLicenceAndArtwork() throws {
        let notices = try Self.text("Resources/THIRD_PARTY_NOTICES.txt")
        let resources = Self.root.appendingPathComponent("Resources")
        let names = try FileManager.default.contentsOfDirectory(atPath: resources.path)

        // Every font the app bundles, by family, with its licence file.
        for font in names where font.hasSuffix(".ttf") || font.hasSuffix(".otf") {
            XCTAssertTrue(notices.contains("Spline Sans Mono") || !font.hasPrefix("SplineSansMono"), font)
            XCTAssertEqual(font, "SplineSansMono.ttf", "a new font needs its own notice line")
        }
        XCTAssertTrue(notices.contains("SIL Open Font License"))
        XCTAssertTrue(notices.contains("OFL.txt"))

        // Every bundled licence file is referenced.
        for licence in ["OFL.txt", "LICENSE"] {
            XCTAssertTrue(notices.contains(licence), "\(licence) is referenced")
        }
        XCTAssertTrue(notices.contains("MIT License"), "the app's own code and the matrix data are MIT")
        XCTAssertTrue(notices.contains("led-fonts.json") && notices.contains("markup_icons.json"),
                      "the vendored matrix data (Resources/Matrix) is credited")

        // The taco art: the owner's exact wording, and never MIT.
        XCTAssertTrue(notices.contains(Self.tacoCredit), "the taco credit, word for word")
        for line in notices.components(separatedBy: "\n") where line.localizedCaseInsensitiveContains("taco") {
            XCTAssertFalse(line.contains("MIT"), "the taco art is not MIT: \(line)")
        }
        XCTAssertTrue(names.contains("TacoLoader"), "the credit covers Resources/TacoLoader")
        XCTAssertTrue(notices.contains("Resources/TacoLoader") && notices.contains("TacoMark"),
                      "the credit names both pieces of taco art")
    }

    /// Swift packages: credited by name, and none ships in the app or its
    /// extension (so "no third-party runtime packages" stays true).
    func testEverySwiftPackageIsCreditedAndNoneShips() throws {
        let project = try Self.text("project.yml")
        let notices = try Self.text("Resources/THIRD_PARTY_NOTICES.txt")
        // `packages:` keys, two-space indented, before `settings:`.
        let block = project.components(separatedBy: "\npackages:\n").dropFirst().first?
            .components(separatedBy: "\nsettings:").first ?? ""
        let packages = block.components(separatedBy: "\n").compactMap { line -> String? in
            guard line.hasPrefix("  "), !line.hasPrefix("    "), line.hasSuffix(":") else { return nil }
            return String(line.dropFirst(2).dropLast())
        }
        XCTAssertFalse(packages.isEmpty, "project.yml's packages were read")
        for package in packages {
            XCTAssertTrue(notices.contains(package) || notices.contains("swift-snapshot-testing") && package == "SnapshotTesting",
                          "\(package) is credited")
        }
        // Only test targets depend on a package.
        let targets = project.components(separatedBy: "\ntargets:\n").dropFirst().first?
            .components(separatedBy: "\nschemes:").first ?? ""
        var target = ""
        var linking: [String] = []
        for line in targets.components(separatedBy: "\n") {
            if line.hasPrefix("  "), !line.hasPrefix("   "), line.hasSuffix(":") {
                target = String(line.dropFirst(2).dropLast())
            } else if line.contains("- package:") {
                linking.append(target)
            }
        }
        XCTAssertFalse(linking.isEmpty, "the test target's package was found")
        for name in linking {
            XCTAssertTrue(name.hasSuffix("Tests"), "\(name) links a package; credit it as shipped")
        }
    }

    /// Settings › About & help › Licenses shows every notice the app bundles.
    func testTheLicensesPageShowsTheNotices() throws {
        let entries = SettingsCopy.licenses(bundle: Self.appBundle)
        XCTAssertEqual(entries.map(\.name), ["Notices", "Spline Sans Mono", "MIT License"])
        XCTAssertEqual(entries.first?.text, try Self.text("Resources/THIRD_PARTY_NOTICES.txt"),
                       "the page shows the bundled notices file")
        for entry in entries { XCTAssertGreaterThan(entry.text.count, 200, "\(entry.name) is the full text") }
        XCTAssertTrue(entries[0].text.contains(Self.tacoCredit))
    }

    // MARK: Version and changelog

    private static func setting(_ key: String) throws -> String {
        let project = try text("project.yml")
        let line = try XCTUnwrap(project.components(separatedBy: "\n").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix(key + ":") })
        return line.components(separatedBy: ":").dropFirst().joined(separator: ":")
            .trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    func testTheChangelogLeadsWithTheVersionInProjectYml() throws {
        let version = try Self.setting("MARKETING_VERSION")
        let changelog = try Self.text("CHANGELOG.md")
        let top = try XCTUnwrap(changelog.components(separatedBy: "\n").first { $0.hasPrefix("## ") }, "a version heading")
        XCTAssertTrue(top.hasPrefix("## \(version) "), "CHANGELOG's newest entry is \(version): \(top)")
    }

    /// Both plists carry project.yml's numbers, and the Top Shelf extension
    /// matches its app (an upload rejects a mismatch).
    func testTheBuiltAppAndExtensionCarryTheProjectVersion() throws {
        let version = try Self.setting("MARKETING_VERSION")
        let build = try Self.setting("CURRENT_PROJECT_VERSION")
        let app = Self.appBundle
        XCTAssertEqual(app.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, version)
        XCTAssertEqual(app.object(forInfoDictionaryKey: "CFBundleVersion") as? String, build)
        let plugin = try XCTUnwrap(app.builtInPlugInsURL?.appendingPathComponent("FiestaBoardTopShelf.appex"))
        let shelf = try XCTUnwrap(Bundle(url: plugin), "the Top Shelf extension is embedded")
        XCTAssertEqual(shelf.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, version)
        XCTAssertEqual(shelf.object(forInfoDictionaryKey: "CFBundleVersion") as? String, build)
    }

    // MARK: App Store listing

    /// App Store Connect's limits, read from the files deliver uploads.
    func testTheListingFitsAppStoreConnect() throws {
        let limits: [(String, Int)] = [("name", 30), ("subtitle", 30), ("promotional_text", 170),
                                       ("keywords", 100), ("description", 4000)]
        for (field, limit) in limits {
            let value = try Self.text("fastlane/metadata/en-US/\(field).txt").trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertFalse(value.isEmpty, field)
            XCTAssertLessThanOrEqual(value.count, limit, "\(field): \(value.count) characters")
        }
    }

    // MARK: Privacy, three ways

    /// docs/PRIVACY.md (the published policy), the in-app Privacy page and
    /// the privacy manifest say the same things.
    func testThePublishedPolicyMatchesTheInAppPrivacyText() throws {
        let policy = try Self.text("docs/PRIVACY.md")
        let inApp = SettingsCopy.privacyBody(tvName: "Living Room")
        // Shared facts, each in both.
        let facts: [(inApp: String, policy: String)] = [
            ("no analytics or tracking", "analytics"),
            ("Keychain", "Keychain"),
            ("revocable TV credential", "revocable TV credential"),
            ("Displays › Living Room › Shown on", "Displays › *your TV* › Shown on"),
            ("not saved after a TV credential is issued", "not retained after that credential is issued"),
        ]
        for fact in facts {
            XCTAssertTrue(inApp.contains(fact.inApp), "in-app: \(fact.inApp)")
            XCTAssertTrue(policy.contains(fact.policy), "PRIVACY.md: \(fact.policy)")
        }
        // The hub is "hub" in the policy outside the FiestaBot section, which
        // A9 deletes with the feature.
        var outsideAI = policy
        if let start = policy.range(of: "## Optional AI features"),
           let end = policy.range(of: "\n## ", range: start.upperBound..<policy.endIndex) {
            outsideAI.removeSubrange(start.lowerBound..<end.lowerBound)
        }
        XCTAssertFalse(outsideAI.contains("FiestaBoard server"), "PRIVACY.md calls it the FiestaBoard hub")
        // The FiestaBot disclosure exists in both places or in neither (A9).
        // Read from source, so this check survives A9 deleting the branch.
        let appHasAI = try Self.text("Sources/UI/SettingsCopy.swift").contains("AI provider")
        XCTAssertEqual(policy.contains("## Optional AI features"), appHasAI,
                       "PRIVACY.md and the in-app Privacy page drop FiestaBot together")
        // The listing links the policy; the manifest declares no tracking.
        XCTAssertTrue(try Self.text("fastlane/metadata/en-US/privacy_url.txt").contains("docs/PRIVACY.md"))
        let manifest = try Self.text("Resources/PrivacyInfo.xcprivacy")
        XCTAssertTrue(manifest.contains("<key>NSPrivacyTracking</key>\n\t<false/>")
                      || manifest.range(of: "NSPrivacyTracking</key>\\s*<false/>", options: .regularExpression) != nil)
    }

    // MARK: The hardware half

    /// docs/HARDWARE-CHECKLIST.md covers every item A12 leaves to a real
    /// Apple TV, each with how to measure it and its threshold.
    func testTheHardwareChecklistCoversEveryDeviceItem() throws {
        let checklist = try Self.text("docs/HARDWARE-CHECKLIST.md")
        for item in ["VoiceOver", "Liquid Glass", "Top Shelf", "DD26", "LED redraw", "Cold start", "24-hour memory soak",
                     "OLED care", "Siri Remote", "TestFlight", "App Store review", "O6", "O10"] {
            XCTAssertTrue(checklist.contains(item), item)
        }
        let sections = checklist.components(separatedBy: "\n## ").dropFirst().filter { $0.first?.isNumber == true }
        XCTAssertGreaterThanOrEqual(sections.count, 11)
        for section in sections {
            let title = section.components(separatedBy: "\n").first ?? ""
            XCTAssertTrue(section.contains("**How:**"), "\(title): how to measure")
            XCTAssertTrue(section.contains("**Pass:**"), "\(title): its threshold")
        }
    }
}
