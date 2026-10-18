import Foundation

@MainActor enum TrainingSync {
    private static var retrying = Set<String>()
    static func prefix(_ api: APIClient, _ userId: Int) -> String { "training:\(api.baseURL.absoluteString):\(userId):" }
    static func send(api: APIClient, userId: Int, path: String, body: [String: Any], id: String) async throws {
        let key = prefix(api, userId) + id
        let record: [String: Any] = ["path": path, "body": body]
        let bytes = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        UserDefaults.standard.set(bytes, forKey: key)
        let _: EmptyResponse = try await api.request(path, method: "POST", body: body)
        if UserDefaults.standard.data(forKey: key) == bytes { UserDefaults.standard.removeObject(forKey: key) }
    }
    static func retry(api: APIClient, userId: Int) async {
        let scope = prefix(api, userId)
        guard retrying.insert(scope).inserted else { return }
        defer { retrying.remove(scope) }
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where key.hasPrefix(prefix(api, userId)) {
            guard let data = value as? Data, let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let path = saved["path"] as? String, let body = saved["body"] as? [String: Any] else { continue }
            guard !Task.isCancelled else { return }
            do {
                let _: EmptyResponse = try await api.request(path, method: "POST", body: body)
                if UserDefaults.standard.data(forKey: key) == data { UserDefaults.standard.removeObject(forKey: key) }
            } catch is CancellationError { return }
            catch {
                let status = (error as? ClientError)?.status ?? 0
                if status == 0 || status == 401 || status >= 500 { return }
            }
        }
    }
}
