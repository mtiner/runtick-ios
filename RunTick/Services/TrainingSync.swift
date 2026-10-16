import Foundation

@MainActor enum TrainingSync {
    static func prefix(_ api: APIClient, _ userId: Int) -> String { "training:\(api.baseURL.absoluteString):\(userId):" }
    static func send(api: APIClient, userId: Int, path: String, body: [String: Any], id: String) async throws {
        let key = prefix(api, userId) + id
        let record: [String: Any] = ["path": path, "body": body]
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: record), forKey: key)
        let _: EmptyResponse = try await api.request(path, method: "POST", body: body)
        UserDefaults.standard.removeObject(forKey: key)
    }
    static func retry(api: APIClient, userId: Int) async {
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where key.hasPrefix(prefix(api, userId)) {
            guard let data = value as? Data, let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let path = saved["path"] as? String, let body = saved["body"] as? [String: Any] else { continue }
            do { let _: EmptyResponse = try await api.request(path, method: "POST", body: body); UserDefaults.standard.removeObject(forKey: key) } catch { return }
        }
    }
}
