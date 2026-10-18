import Foundation

struct AvatarOption: Decodable, Identifiable {
    let filename: String
    var id: String { filename }
    var title: String { String(filename.dropLast(4)) }
    var url: URL? { AvatarImageURL.make(filename) }
}
struct AvatarGallery: Decodable { let avatars: [AvatarOption] }

enum AvatarImageURL {
    private static let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ._-")
    static func make(_ filename: String?) -> URL? {
        guard let filename, filename.count > 4, filename.hasSuffix(".png"), !filename.contains(".."),
              filename.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return URL(string: "https://download.runtick.cc/avatar/")!.appendingPathComponent(filename)
    }
}
