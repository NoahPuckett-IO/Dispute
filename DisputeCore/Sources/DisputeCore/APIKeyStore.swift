import Foundation
import Security

/// Where the Mistral API key lives.
///
/// The Keychain rather than `UserDefaults`, which is a plist in the app's
/// container that goes into iCloud and device backups. A key typed in here would
/// otherwise end up in a backup of every phone the person ever restores from,
/// which is a way to leak somebody's credential without ever meaning to.
///
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` keeps it off backups and
/// off other devices while still allowing a call to be made when the phone is
/// locked — which matters, because a session can be running while the screen
/// goes off.
public struct APIKeyStore: Sendable {
    private let service: String

    /// The provider the stored key belongs to.
    ///
    /// Part of the Keychain query rather than cosmetic, and that is the point: a
    /// key issued by the previous provider cannot authenticate a request to this
    /// one, so the two must not share a slot. Changing this string is what makes
    /// an upgrading phone read as "no key stored" rather than as "a key that
    /// fails every request" — which is the worse of the two by a distance,
    /// because the screen would send somebody to check a key that was correct
    /// when they typed it.
    private let account = "mistral"

    /// Slots this app used to keep keys in.
    ///
    /// Emptied rather than left alone. A revoked credential sitting in the
    /// Keychain of everybody who ever used the Gemini builds is a small leak that
    /// nothing in the app would ever read again, and "delete everything" in
    /// Settings would not have touched it either.
    private static let retiredAccounts = ["gemini"]

    public init(service: String = "com.jamesgpuckett.Dispute.apikey") {
        self.service = service
    }

    public var key: String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8)
        else { return nil }

        let trimmed = text.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }

    public var hasKey: Bool { key != nil }

    /// Stores a key, replacing any already there. An empty string deletes.
    ///
    /// Empty means delete because that is what clearing the field means, and
    /// storing "" would leave a key that exists, fails every request, and cannot
    /// be told apart from a real one that has been revoked.
    @discardableResult
    public func setKey(_ key: String?) -> Bool {
        let trimmed = (key ?? "").trimmed
        guard !trimmed.isEmpty else { return removeKey() }
        guard let data = trimmed.data(using: .utf8) else { return false }

        let attributes: [String: Any] = [kSecValueData as String: data]
        let updated = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }

        var insert = baseQuery
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    public func removeKey() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Drops keys left behind by a previous provider.
    ///
    /// Called once on launch. Safe to call when there is nothing there —
    /// `errSecItemNotFound` is the ordinary answer and not a failure — and safe
    /// to call twice, which matters because the alternative was a flag in
    /// `UserDefaults` recording whether it had run, and that flag would outlive
    /// its own reason for existing.
    public func forgetRetiredKeys() {
        for retired in Self.retiredAccounts {
            SecItemDelete(query(account: retired) as CFDictionary)
        }
    }

    private var baseQuery: [String: Any] { query(account: account) }

    private func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
