import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private struct Envelope<T: Decodable>: Decodable {
    let ok: Bool; let data: T?; let error: ErrorPayload?
    struct ErrorPayload: Decodable { let code: String; let message: String }
}
@MainActor final class APIClient {
    let baseURL: URL
    let session: URLSession
    private let sessionStore: SessionStore
    var unauthorized: (() -> Void)?
    init(baseURL: URL) {
        self.baseURL = baseURL
        sessionStore = SessionStore(server: baseURL)
        if let cookie = sessionStore.restore() { HTTPCookieStorage.shared.setCookie(cookie) }
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        session = URLSession(configuration: configuration)
    }
    func url(_ path: String) -> URL { URL(string: path, relativeTo: baseURL)!.absoluteURL }
    func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        var request = URLRequest(url: url(path)); request.httpMethod = method
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let data: Data; let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            if Task.isCancelled { throw CancellationError() }
            if let network = error as? URLError {
                if network.code == .timedOut { throw ClientError.message("连接服务器超时，请稍后重试。") }
                if network.code == .notConnectedToInternet || network.code == .networkConnectionLost { throw ClientError.message("网络连接已断开。请检查 Wi-Fi 或蜂窝网络后重试。") }
            }
            throw ClientError.message("暂时无法连接服务器，请检查网络后重试。")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            clearCookies()
            unauthorized?()
        } else if let response = response as? HTTPURLResponse {
            // Save Set-Cookie before returning login, without waiting for the OS cookie cache to flush.
            let headers = response.allHeaderFields.reduce(into: [String: String]()) { fields, pair in
                if let key = pair.key as? String, let value = pair.value as? String { fields[key] = value }
            }
            for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: response.url ?? baseURL)
                where cookie.name == "runtick_session" {
                if SavedSessionCookie(cookie).cookie(for: baseURL) == nil {
                    sessionStore.clear()
                    HTTPCookieStorage.shared.deleteCookie(cookie)
                } else {
                    HTTPCookieStorage.shared.setCookie(cookie)
                    try sessionStore.save(cookie)
                }
            }
        }
        let envelope = try? JSONDecoder().decode(Envelope<T>.self, from: data)
        guard (200..<300).contains(status), let envelope, envelope.ok, let value = envelope.data else {
            throw ClientError(status: status, code: envelope?.error?.code ?? "UNKNOWN", message: envelope?.error?.message ?? "请求失败，请稍后重试")
        }
        return value
    }
    var savedUser: User? { sessionStore.read()?.user }
    func remember(_ user: User) throws {
        if let cookie = (HTTPCookieStorage.shared.cookies(for: baseURL) ?? []).first(where: { $0.name == "runtick_session" }) {
            try sessionStore.save(cookie, user: user)
        }
    }
    func clearCookies() {
        sessionStore.clear()
        for cookie in HTTPCookieStorage.shared.cookies(for: baseURL) ?? [] { HTTPCookieStorage.shared.deleteCookie(cookie) }
    }
    func socketRequest(code: String) -> URLRequest {
        var parts = URLComponents(url: url("/api/rooms/\(code)/ws"), resolvingAgainstBaseURL: false)!
        parts.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        var request = URLRequest(url: parts.url!)
        let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) ?? []
        for (key, value) in HTTPCookie.requestHeaderFields(with: cookies) { request.setValue(value, forHTTPHeaderField: key) }
        return request
    }
}
