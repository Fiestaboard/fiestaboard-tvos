import XCTest
import Security
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
        try? store.deleteAll()
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

    /// The blob used to be "username\npassword" split on the first newline,
    /// so this pair came back as ("a", "b\np") with no error at all — which
    /// presents as "the board keeps logging me out", because every silent
    /// re-login then fails and trips the rejected-credential cooldown.
    func testANewlineInEitherFieldSurvives() throws {
        try store.save(StoredCredential(username: "a\nb", password: "p\nq"), for: "host")
        let loaded = store.load(for: "host")
        XCTAssertEqual(loaded?.username, "a\nb")
        XCTAssertEqual(loaded?.password, "p\nq")
    }

    /// A credential written by a pre-JSON build must still load. Failing to
    /// decode would silently sign a tester out and ask for a password again,
    /// which is a worse bug than the one the JSON change fixes. Delete this
    /// test with the fallback, once no pre-JSON build is in the field.
    func testACredentialFromAPreJSONBuildStillLoads() throws {
        writeLegacyBlob("jeffre\nhunter2", for: "host")
        let loaded = store.load(for: "host")
        XCTAssertEqual(loaded?.username, "jeffre")
        XCTAssertEqual(loaded?.password, "hunter2")
    }

    /// Whatever the old blob was, it must never be mistaken for a credential
    /// when there is no separator at all.
    func testAnUnreadableBlobIsNil() throws {
        writeLegacyBlob("nothing-separable", for: "host")
        XCTAssertNil(store.load(for: "host"))
    }

    /// The reason `deleteAll` is on the protocol at all — the argument is
    /// written out on `CredentialStore.deleteAll`. "Forget this board" has to
    /// clear the service, not one account.
    func testDeleteAllRemovesEverySpelling() throws {
        try store.save(StoredCredential(username: "a", password: "1"),
                       for: "http://kitchen.local:4420")
        try store.save(StoredCredential(username: "a", password: "1"),
                       for: "http://192.168.1.50:4420")

        try store.deleteAll()

        XCTAssertNil(store.load(for: "http://kitchen.local:4420"))
        XCTAssertNil(store.load(for: "http://192.168.1.50:4420"))
    }

    func testDeletingEverythingWhenThereIsNothingIsNotAnError() {
        XCTAssertNoThrow(try store.deleteAll())
    }

    /// "Every credential this app owns" is the whole of the claim, and only
    /// the first half of it was tested: that the items go. The query carries
    /// `kSecAttrService` precisely so the other half holds too, and dropping
    /// it turns "Forget this board" into a delete of every generic-password
    /// item the process can reach — which no assertion here would have felt.
    func testDeleteAllIsScopedToThisAppsService() throws {
        let other = KeychainCredentialStore(
            service: "com.fiestaboard.tv.tests.other.\(UUID().uuidString)")
        defer { try? other.deleteAll() }
        try other.save(StoredCredential(username: "someone", password: "else"), for: "host")
        try store.save(StoredCredential(username: "a", password: "1"), for: "host")

        try store.deleteAll()

        XCTAssertNil(store.load(for: "host"))
        XCTAssertEqual(other.load(for: "host")?.password, "else",
                       "deleteAll must not reach past this app's own service")
    }

    func testInMemoryStoreMatchesTheProtocol() throws {
        let mem = InMemoryCredentialStore()
        try mem.save(StoredCredential(username: "a", password: "1"), for: "h")
        XCTAssertEqual(mem.load(for: "h")?.username, "a")
        try mem.delete(for: "h")
        XCTAssertNil(mem.load(for: "h"))

        try mem.save(StoredCredential(username: "a", password: "1"), for: "h1")
        try mem.save(StoredCredential(username: "b", password: "2"), for: "h2")
        try mem.deleteAll()
        XCTAssertNil(mem.load(for: "h1"))
        XCTAssertNil(mem.load(for: "h2"))
    }

    // MARK: Helpers

    /// Put a raw blob in the keychain the way a pre-JSON build would have,
    /// bypassing `save` — the point is to read what an older binary wrote.
    private func writeLegacyBlob(_ blob: String, for account: String) {
        try? store.delete(for: account)
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service as String,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(blob.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        XCTAssertEqual(SecItemAdd(item as CFDictionary, nil), errSecSuccess)
    }
}
