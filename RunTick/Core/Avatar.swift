import Foundation

struct AvatarOption: Decodable, Identifiable {
    let filename: String
    var description: String? = nil
    var id: String { filename }
    var title: String { description ?? String(filename.dropLast(4)) }
    var url: URL? { AvatarImageURL.make(filename) }
}
struct AvatarGallery: Decodable { let avatars: [AvatarOption] }

enum AvatarImageURL {
    private static let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ._-")
    static func make(_ filename: String?) -> URL? {
        guard let filename, filename.count > 4, filename.hasSuffix(".png"), !filename.contains(".."),
              filename.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        if !filename.contains(" ") && filename != "default.png" && filename == filename.lowercased() {
            return URL(string:"https://api.runtick.cc/api/avatars/")!.appendingPathComponent(filename)
        }
        return URL(string: "https://download.runtick.cc/avatar/")!.appendingPathComponent(filename)
    }
}
