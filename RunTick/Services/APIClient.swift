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
    var unauthorized: (() -> Void)?
    init(baseURL: URL) {
        self.baseURL = baseURL
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
        catch { if Task.isCancelled { throw CancellationError() }; throw ClientError.message("网络不可用，请检查连接后重试") }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { unauthorized?() }
        let envelope = try? JSONDecoder().decode(Envelope<T>.self, from: data)
        guard (200..<300).contains(status), let envelope, envelope.ok, let value = envelope.data else {
            throw ClientError(status: status, code: envelope?.error?.code ?? "UNKNOWN", message: envelope?.error?.message ?? "请求失败，请稍后重试")
        }
        return value
    }
    func clearCookies() {
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
