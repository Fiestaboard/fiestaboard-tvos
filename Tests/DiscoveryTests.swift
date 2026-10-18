import Foundation
import Network
import XCTest
@testable import FiestaBoardTV

final class DiscoveryTests: XCTestCase {

    func testDiscoversExistingFiestaPiByItsBonjourHostname() async {
        let discovery = BonjourDiscovery(probe: { $0.host() == "fiestapi.local" },
                                         browseServices: false)
        let found = expectation(description: "FiestaPi hostname is probed during discovery")
        let stream = Task {
            for await boards in discovery.boards() {
                if boards.contains(where: { $0.host.host() == "fiestapi.local" }) {
                    found.fulfill()
                    break
                }
            }
        }

        await fulfillment(of: [found], timeout: 5)
        discovery.stop()
        stream.cancel()
    }

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

    /// ...and only for those. A service that publishes TXT without claiming
    /// `product=FiestaBoard` is not ours whatever it calls itself; accepting
    /// the name alone let anything on the LAN offer itself as a board, and
    /// both shipping advertisers (the Pi image's Avahi file and the server's
    /// zeroconf registration) send the record.
    func testTheNameFallbackAppliesOnlyWhenThereIsNoTXTAtAll() {
        XCTAssertFalse(DiscoveryFilter.isFiestaBoard(candidate(name: "FiestaBoard", txt: ["path": "/"])))
        XCTAssertFalse(DiscoveryFilter.isFiestaBoard(candidate(name: "FiestaBoard Pro",
                                                               txt: ["product": "Definitely Not"])))
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

    func testScopedIPv6PreservesTheRequiredInterface() {
        XCTAssertEqual(BonjourDiscovery.hostString(from: .ipv6(IPv6Address("fe80::1%en0")!)),
                       "fe80::1%en0")
        XCTAssertEqual(DiscoveryFilter.url(for: candidate(host: "fe80::1%en0"))?.absoluteString,
                       "http://[fe80::1%25en0]:4420")
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

    /// The string people paste out of a browser address bar has a scheme and
    /// no port, and URL reads that as port 80 — so a perfectly good address
    /// came back "Couldn't reach", blaming the network for a missing port.
    func testSchemedHTTPHostWithNoPortGetsTheDefaultPort() {
        XCTAssertEqual(ManualAddress.parse("http://192.168.0.50")?.absoluteString,
                       "http://192.168.0.50:4420")
        XCTAssertEqual(ManualAddress.parse("  http://fiestaboard.local/  ")?.absoluteString,
                       "http://fiestaboard.local:4420")
    }

    func testSchemeWithNoHostIsRejected() {
        XCTAssertNil(ManualAddress.parse("http://"))
        XCTAssertNil(ManualAddress.parse("https://"))
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

    // MARK: The confirmation probe

    /// The probe used to run on FiestaClient's default configuration, which is
    /// backed by `HTTPCookieStorage.shared` — the jar holding the live board
    /// session. Cookies are scoped by domain and path but never by port, so
    /// merely opening Connect handed that session cookie to anything answering
    /// on the board's hostname, `fiestapi.local` included. `/auth/status` is
    /// public, so the probe gives up nothing by being anonymous.
    func testTheProbeSessionIsAnonymous() {
        let config = BonjourDiscovery.probeConfiguration()
        XCTAssertNil(config.httpCookieStorage)
        XCTAssertFalse(config.httpShouldSetCookies)
        XCTAssertEqual(config.httpCookieAcceptPolicy, .never)
        XCTAssertEqual(config.timeoutIntervalForRequest, 5)
        XCTAssertNotEqual(config.requestCachePolicy, .useProtocolCachePolicy)
    }

    /// The session actually handed to FiestaClient, not just the recipe.
    func testTheProbeSessionKeepsTheAnonymousConfiguration() {
        let session = BonjourDiscovery.probeSession()
        XCTAssertNil(session.configuration.httpCookieStorage)
        XCTAssertFalse(session.configuration.httpShouldSetCookies)
    }

    /// Both tests above assert the recipe. Neither asserts the probe eats it:
    /// deleting `session: Self.sharedProbeSession` from the default probe in
    /// `init` restores the cookie leak in full and leaves both of them green.
    /// So this one asserts on the wire instead — a cookie in the shared jar
    /// for the probed host, the *default* probe (no injection, the production
    /// closure), and a loopback server that records what it is actually sent.
    ///
    /// It has to be a real socket. `StubURLProtocol` sits above the layer that
    /// attaches cookies — CFNetwork adds the header on its way to the HTTP
    /// protocol, which a custom `URLProtocol` replaces — so a stub sees no
    /// `Cookie` header whether or not the session carries a jar, and would
    /// pass just as happily on the leaking code.
    ///
    /// The control request is what makes the negative assertion mean anything:
    /// it proves this jar really does reach this host on a default session, so
    /// a missing header below is the probe declining the cookie rather than
    /// the fixture never having had one to send.
    func testTheDefaultProbeSendsNoCookieToTheHostItProbes() async throws {
        let server = try ProbeRecordingServer()
        defer { server.stop() }

        let jar = HTTPCookieStorage.shared
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "127.0.0.1",
            .path: "/",
            .name: "session",
            .value: "live-board-session",
        ]))
        jar.setCookie(cookie)
        defer { jar.deleteCookie(cookie) }

        _ = try? await FiestaClient(baseURL: server.url).authStatus()
        let control = try XCTUnwrap(server.requests.first,
                                    "the control request never reached the fixture")
        XCTAssertTrue(control.contains("Cookie: session=live-board-session"),
                      "the jar no longer reaches this host, so this test can no longer "
                      + "detect the leak it exists for: \(control)")

        let discovery = BonjourDiscovery()
        await discovery.confirm(url: server.url, name: "FiestaBoard")

        XCTAssertEqual(server.requests.count, 2, "the probe never reached the fixture")
        let probe = server.requests.last ?? ""
        XCTAssertTrue(probe.hasPrefix("GET /api/auth/status "),
                      "the probe should ask the public endpoint: \(probe)")
        XCTAssertFalse(probe.lowercased().contains("\r\ncookie:"),
                       "the discovery probe handed the live board session to a probed "
                       + "host: \(probe)")
    }

    // MARK: Boards that are still booting

    private static let bootingBoard = URL(string: "http://board.local:4420")!
    private static let bootingEndpoint = NWEndpoint.service(name: "FiestaBoard",
                                                            type: "_http._tcp",
                                                            domain: "local.",
                                                            interface: nil)

    /// A board whose mDNS record is up before its HTTP server is — the thirty
    /// to sixty seconds after a power cut, when nginx answers 503 and the
    /// probe comes back nil.
    ///
    /// `BonjourDiscovery` gates re-resolving on a set of endpoints it has
    /// already started, because a browse callback hands over the whole result
    /// set and would otherwise re-probe every board on screen. That set was
    /// cleared on a failed connection but not on a failed probe, so a booting
    /// board was skipped for the rest of the browse — while the Connect
    /// screen went on promising the Apple TV was still listening for it.
    func testABoardThatRefusesTheFirstProbeIsTriedAgainAndAppears() async {
        let log = ProbeLog()
        let browsing = expectation(description: "the browse is running")
        browsing.assertForOverFulfill = false
        let discovery = BonjourDiscovery(probe: { url in
            let host = url.host() ?? ""
            let attempt = await log.record(host)
            // The legacy hostname probe fires only once the stream's
            // continuation is installed, which is what `confirm` below needs.
            if host == "fiestapi.local" { browsing.fulfill() }
            return host == "board.local" && attempt > 1
        }, browseServices: false)

        let appeared = expectation(description: "the board appears once it answers")
        let stream = Task {
            for await boards in discovery.boards() {
                if boards.contains(where: { $0.host == Self.bootingBoard }) {
                    appeared.fulfill()
                    break
                }
            }
        }
        await fulfillment(of: [browsing], timeout: 5)

        await discovery.confirm(url: Self.bootingBoard, name: "FiestaBoard",
                                endpoint: Self.bootingEndpoint)

        await fulfillment(of: [appeared], timeout: 15)
        let probes = await log.count(for: "board.local")
        XCTAssertGreaterThanOrEqual(probes, 2, "a refused probe must leave the endpoint tryable")

        discovery.stop()
        stream.cancel()
    }

    /// The other half of that tension: handing the endpoint back must not put
    /// back the churn the gate was added to stop. A host that never answers is
    /// worth one probe per backoff window, not one per turn of the queue.
    func testAHostThatNeverAnswersIsNotReprobedImmediately() async {
        let log = ProbeLog()
        let browsing = expectation(description: "the browse is running")
        browsing.assertForOverFulfill = false
        let discovery = BonjourDiscovery(probe: { url in
            let host = url.host() ?? ""
            _ = await log.record(host)
            if host == "fiestapi.local" { browsing.fulfill() }
            return false
        }, browseServices: false)

        let stream = Task { for await _ in discovery.boards() {} }
        await fulfillment(of: [browsing], timeout: 5)

        await discovery.confirm(url: Self.bootingBoard, name: "FiestaBoard",
                                endpoint: Self.bootingEndpoint)
        try? await Task.sleep(for: .seconds(BonjourDiscovery.retryDelay / 2))

        let probes = await log.count(for: "board.local")
        XCTAssertEqual(probes, 1,
                       "a host that is never coming back must not be re-probed in a tight loop")

        discovery.stop()
        stream.cancel()
    }
}

/// A loopback HTTP server that keeps the raw bytes of every request it is
/// sent, so a test can assert on headers the client added on its way out.
/// Nothing above the socket can: cookies are attached below `URLProtocol`.
///
/// `@unchecked Sendable` rests on the lock — `recorded` is the only mutable
/// state and never leaves it.
private final class ProbeRecordingServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "DiscoveryTests.probeServer")
    private let lock = NSLock()
    private var recorded: [String] = []

    var url: URL { URL(string: "http://127.0.0.1:\(listener.port!.rawValue)")! }

    var requests: [String] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed: ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, listener.port != nil else {
            throw NSError(domain: "ProbeRecordingServer", code: 1)
        }
    }

    func stop() { listener.cancel() }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data,
                  let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            // Recorded before the reply goes out, so a caller that has awaited
            // its response is guaranteed to see it.
            self.lock.lock()
            self.recorded.append(request)
            self.lock.unlock()

            let payload = Data(Fixtures.authStatusDisabled.utf8)
            let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(header.utf8) + payload,
                            completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}

/// Counts probes per host, so a test can have one address refuse the first
/// time and answer the second.
private actor ProbeLog {
    private var counts: [String: Int] = [:]

    func record(_ host: String) -> Int {
        let next = (counts[host] ?? 0) + 1
        counts[host] = next
        return next
    }

    func count(for host: String) -> Int { counts[host] ?? 0 }
}
