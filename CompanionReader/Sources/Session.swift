import Foundation
import Security

/// Persisted server URL (UserDefaults) and tokens (Keychain).
final class Session: ObservableObject {
    @Published var loggedIn: Bool
    private let defaults = UserDefaults.standard

    init() {
        loggedIn = false
        loggedIn = !serverUrl.isEmpty && refreshToken != nil
    }

    var serverUrl: String {
        get { defaults.string(forKey: "server") ?? "" }
        set { defaults.set(newValue, forKey: "server") }
    }
    var accessToken: String? {
        get { Keychain.get("access") }
        set { Keychain.set("access", newValue) }
    }
    var refreshToken: String? {
        get { Keychain.get("refresh") }
        set { Keychain.set("refresh", newValue) }
    }

    func clearTokens() {
        accessToken = nil; refreshToken = nil
        DispatchQueue.main.async { self.loggedIn = false }
    }
    func markLoggedIn() { DispatchQueue.main.async { self.loggedIn = true } }
}

enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.bookorb.companion.reader", kSecAttrAccount as String: key]
    }
    static func get(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func set(_ key: String, _ value: String?) {
        SecItemDelete(query(key) as CFDictionary)
        guard let value else { return }
        var q = query(key)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}
