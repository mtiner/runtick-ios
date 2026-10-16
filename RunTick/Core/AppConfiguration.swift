import Foundation

enum AppConfiguration {
    /// H5 gateway forwards REST and WebSocket to the production API, sharing cookies.
    static let serverURL = URL(string: "https://app.runtick.cc/")!
}
