import XCTest
@testable import FiestaBoardTV

final class DiscoveryTests: XCTestCase {

    private func candidate(name: String = "FiestaBoard",
                           host: String = "fiestaboard.local",
                           port: Int = 4420,
                           txt: [String: String] = ["product": "FiestaBoard", "path": "/"]) -> DiscoveryCandidate {
        DiscoveryCandidate(name: name, host: host, port: port, txt: txt)
    }

    // MARK: Filtering

    /// The instance advertises _http._tcp with product=FiestaBoard in TXT,
    /// so that record is what separates it from every printer on the LAN.
    func testAcceptsAServiceAdvertisingTheProductRecord() {
        XCTAssertTrue(DiscoveryFilter.isFiestaBoard(candidate()))
    }

    func testTxtMatchIsCaseInsensitive() {
        XCTAssertTrue(DiscoveryFilter.isFiestaBoard(candidate(txt: ["product": "fiestaboard"])))
        XCTAssertTrue(DiscoveryFilter.isFiestaBoard(candidate(txt: ["Product": "FiestaBoard"])))
    }

    func testRejectsUnrelatedHTTPServices() {
        XCTAssertFalse(DiscoveryFilter.isFiestaBoard(candidate(name: "Brother HL-2270DW", txt: [:])))
        XCTAssertFalse(DiscoveryFilter.isFiestaBoard(candidate(name: "Living Room TV", txt: ["product": "Roku"])))
    }

    /// Fallback for instances too old to publish the TXT record: the service
    /// name itself is "FiestaBoard._http._tcp.local."
    func testFallsBackToTheServiceName() {
        XCTAssertTrue(DiscoveryFilter.isFiestaBoard(candidate(name: "FiestaBoard", txt: [:])))
        XCTAssertTrue(DiscoveryFilter.isFiestaBoard(candidate(name: "fiestaboard", txt: [:])))
    }

    // MARK: URL construction

    func testBuildsAnHTTPURLFromHostAndPort() {
        let url = DiscoveryFilter.url(for: candidate())
        XCTAssertEqual(url?.absoluteString, "http://fiestaboard.local:4420")
    }

    func testAppendsDotLocalWhenBonjourOmitsIt() {
        XCTAssertEqual(DiscoveryFilter.url(for: candidate(host: "fiestaboard"))?.absoluteString,
                       "http://fiestaboard.local:4420")
    }

    /// Bonjour hostnames arrive with a trailing dot; URL(string:) chokes on it.
    func testStripsTheTrailingDot() {
        XCTAssertEqual(DiscoveryFilter.url(for: candidate(host: "fiestaboard.local."))?.absoluteString,
                       "http://fiestaboard.local:4420")
    }

    func testPortEightyIsImplicit() {
        XCTAssertEqual(DiscoveryFilter.url(for: candidate(host: "board.local", port: 80))?.absoluteString,
                       "http://board.local")
    }

    func testIPv6LiteralsAreBracketed() {
        XCTAssertEqual(DiscoveryFilter.url(for: candidate(host: "fe80::1"))?.absoluteString,
                       "http://[fe80::1]:4420")
    }

    // MARK: Manual entry

    /// Typing on a Siri Remote is miserable, so accept the least possible.
    func testBareIPGetsSchemeAndDefaultPort() {
        XCTAssertEqual(ManualAddress.parse("192.168.1.50")?.absoluteString,
                       "http://192.168.1.50:4420")
    }

    func testBareHostnameGetsSchemeAndDefaultPort() {
        XCTAssertEqual(ManualAddress.parse("fiestaboard.local")?.absoluteString,
                       "http://fiestaboard.local:4420")
    }

    func testExplicitPortIsHonoured() {
        XCTAssertEqual(ManualAddress.parse("192.168.1.50:8080")?.absoluteString,
                       "http://192.168.1.50:8080")
    }

    func testFullURLPassesThrough() {
        XCTAssertEqual(ManualAddress.parse("http://192.168.1.50:4420")?.absoluteString,
                       "http://192.168.1.50:4420")
    }

    func testHTTPSIsPreserved() {
        XCTAssertEqual(ManualAddress.parse("https://board.example.com")?.absoluteString,
                       "https://board.example.com")
    }

    func testWhitespaceAndTrailingSlashesAreTrimmed() {
        XCTAssertEqual(ManualAddress.parse("  192.168.1.50/  ")?.absoluteString,
                       "http://192.168.1.50:4420")
    }

    func testBlankInputIsRejected() {
        XCTAssertNil(ManualAddress.parse(""))
        XCTAssertNil(ManualAddress.parse("   "))
    }

    func testTrailingPathIsPreserved() {
        // Reverse-proxied installs live under a subpath.
        XCTAssertEqual(ManualAddress.parse("http://nas.local/fiestaboard")?.absoluteString,
                       "http://nas.local/fiestaboard")
    }
}
