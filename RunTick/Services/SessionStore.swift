import Foundation
import Security

/// Authentication tokens belong in Keychain, never UserDefaults or application logs.
struct SessionStore {
    let server: URL
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "cc.runtick.app") + ".session",
         kSecAttrAccount as String: server.absoluteString]
    }
    func read() -> SavedSessionCookie? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let saved = try? JSONDecoder().decode(SavedSessionCookie.self, from: data),
              saved.cookie(for: server) != nil else { return nil }
        return saved
    }
    func restore() -> HTTPCookie? { read()?.cookie(for: server) }
    func save(_ cookie: HTTPCookie, user: User? = nil) throws {
        var saved = SavedSessionCookie(cookie)
        let previous = read()
        saved.user = user ?? (previous?.value == cookie.value ? previous?.user : nil)
        let data = try JSONEncoder().encode(saved)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw ClientError.message("无法安全保存登录状态，请重试登录。")
        }
    }
    func clear() { SecItemDelete(query as CFDictionary) }
}
