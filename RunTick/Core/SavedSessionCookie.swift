import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Persist the server's expiry unchanged; never turn an expired session into a new one.
struct SavedSessionCookie: Codable {
    var user: User?
    let value: String
    let domain: String
    let path: String
    let secure: Bool
    let expires: Date?

    init(_ cookie: HTTPCookie) {
        value = cookie.value; domain = cookie.domain; path = cookie.path
        secure = cookie.isSecure; expires = cookie.expiresDate
    }

    func cookie(for server: URL, now: Date = Date()) -> HTTPCookie? {
        let host = server.host?.lowercased() ?? ""
        let cookieDomain = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !value.isEmpty, !host.isEmpty, host == cookieDomain || host.hasSuffix("." + cookieDomain),
              !secure || server.scheme == "https", expires.map({ $0 > now }) ?? true else { return nil }
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: "runtick_session", .value: value, .domain: domain, .path: path,
            HTTPCookiePropertyKey("HttpOnly"): "TRUE"
        ]
        if secure { properties[.secure] = "TRUE" }
        if let expires { properties[.expires] = expires }
        return HTTPCookie(properties: properties)
    }
}
