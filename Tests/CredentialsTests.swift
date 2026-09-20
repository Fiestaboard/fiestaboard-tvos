import XCTest
@testable import FiestaBoardTV

final class CredentialsTests: XCTestCase {

    private var service: String!
    private var store: KeychainCredentialStore!

    override func setUp() {
        super.setUp()
        // Never touch the developer's real keychain.
        service = "com.fiestaboard.tv.tests.\(UUID().uuidString)"
        store = KeychainCredentialStore(service: service)
    }

    override func tearDown() {
        try? store.delete(for: "host")
        super.tearDown()
    }

    func testRoundTripsACredential() throws {
        try store.save(StoredCredential(username: "jeffre", password: "hunter2"), for: "host")
        let loaded = store.load(for: "host")
        XCTAssertEqual(loaded?.username, "jeffre")
        XCTAssertEqual(loaded?.password, "hunter2")
    }

    func testMissingCredentialIsNil() {
        XCTAssertNil(store.load(for: "never-saved"))
    }

    /// Saving twice must update rather than throw a duplicate-item error.
    func testSaveOverwrites() throws {
        try store.save(StoredCredential(username: "a", password: "1"), for: "host")
        try store.save(StoredCredential(username: "b", password: "2"), for: "host")
        XCTAssertEqual(store.load(for: "host")?.username, "b")
        XCTAssertEqual(store.load(for: "host")?.password, "2")
    }

    func testDeleteRemoves() throws {
        try store.save(StoredCredential(username: "a", password: "1"), for: "host")
        try store.delete(for: "host")
        XCTAssertNil(store.load(for: "host"))
    }

    func testDeletingSomethingAbsentIsNotAnError() {
        XCTAssertNoThrow(try store.delete(for: "never-saved"))
    }

    func testPasswordsWithNonASCIISurvive() throws {
        try store.save(StoredCredential(username: "jeffre", password: "pä§§wörd✓"), for: "host")
        XCTAssertEqual(store.load(for: "host")?.password, "pä§§wörd✓")
    }

    func testInMemoryStoreMatchesTheProtocol() throws {
        let mem = InMemoryCredentialStore()
        try mem.save(StoredCredential(username: "a", password: "1"), for: "h")
        XCTAssertEqual(mem.load(for: "h")?.username, "a")
        try mem.delete(for: "h")
        XCTAssertNil(mem.load(for: "h"))
    }
}
