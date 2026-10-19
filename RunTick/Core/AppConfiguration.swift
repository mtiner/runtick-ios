import Foundation

enum AppConfiguration {
    /// Gateway forwards REST to the production API, sharing cookies.
    static let serverURL = URL(string: "https://app.runtick.cc/")!
}
