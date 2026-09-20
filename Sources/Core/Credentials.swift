import Foundation
import Security

public struct StoredCredential: Equatable, Sendable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

/// Where the app keeps the credential it re-logs in with.
///
/// A protocol so tests never touch a real keychain, and so the Android port
/// has an obvious seam (EncryptedSharedPreferences).
public protocol CredentialStore: AnyObject {
    func save(_ credential: StoredCredential, for account: String) throws
    func load(for account: String) -> StoredCredential?
    func delete(for account: String) throws
}

public enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
}

/// Keychain-backed store.
///
/// The username is the keychain account and the password is the secret, so
/// one host maps to one item. Items are `WhenUnlockedThisDeviceOnly`: a TV
/// credential has no business syncing to a phone.
public final class KeychainCredentialStore: CredentialStore {

    private let service: String

    public init(service: String = "com.fiestaboard.tv.credentials") {
        self.service = service
    }

    private func query(for account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func save(_ credential: StoredCredential, for account: String) throws {
        // The stored blob is "username\npassword" so one item carries both.
        let blob = Data("\(credential.username)\n\(credential.password)".utf8)

        let update: [String: Any] = [kSecValueData as String: blob]
        let status = SecItemUpdate(query(for: account) as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }

        guard status == errSecItemNotFound else { throw KeychainError.unexpectedStatus(status) }

        var insert = query(for: account)
        insert[kSecValueData as String] = blob
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
    }

    public func load(for account: String) -> StoredCredential? {
        var q = query(for: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let blob = String(data: data, encoding: .utf8) else { return nil }

        // Split on the FIRST newline only: a password may contain more.
        guard let separator = blob.firstIndex(of: "\n") else { return nil }
        return StoredCredential(username: String(blob[blob.startIndex..<separator]),
                                password: String(blob[blob.index(after: separator)...]))
    }

    public func delete(for account: String) throws {
        let status = SecItemDelete(query(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

/// Test double.
public final class InMemoryCredentialStore: CredentialStore {
    private var items: [String: StoredCredential] = [:]

    public init() {}

    public func save(_ credential: StoredCredential, for account: String) throws {
        items[account] = credential
    }

    public func load(for account: String) -> StoredCredential? { items[account] }

    public func delete(for account: String) throws { items[account] = nil }
}
