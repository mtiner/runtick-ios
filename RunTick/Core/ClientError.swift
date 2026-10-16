import Foundation

struct ClientError: LocalizedError {
    let status: Int; let code: String; let message: String
    var errorDescription: String? { message }
    static func message(_ text: String) -> Self { Self(status: 0, code: "CLIENT", message: text) }
}
