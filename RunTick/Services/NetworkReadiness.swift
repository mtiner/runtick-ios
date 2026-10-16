import SwiftUI

@MainActor @Observable final class NetworkReadiness {
    var checking = false
    var attempted = false
    var reachable = false
    var message = "登录、房间同步、校时和成绩保存需要联网。"

    func check() async {
        guard !checking else { return }
        checking = true; attempted = true
        message = "正在连接 Apple 网站…如系统询问，请允许使用无线局域网与蜂窝网络。"
        defer { checking = false }
        // A separate, cookie-free session must never send RunTick credentials to Apple.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.allowsCellularAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://www.apple.com/")!)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await session.data(for: request)
            try Task.checkCancellation()
            reachable = (response as? HTTPURLResponse).map { (200..<400).contains($0.statusCode) } ?? false
            message = reachable ? "已成功访问 Apple 网站。实际房间连接会在使用时单独检测。" : "Apple 网站暂时未能正常响应，可稍后重新检测。"
        } catch {
            guard !Task.isCancelled else { attempted = false; return }
            reachable = false
            message = "暂时无法访问 Apple 网站。请检查网络连接及系统设置中的联网权限，再重新检测。"
        }
    }
}

struct NetworkPreparationCard: View {
    var automaticallyCheck = true
    @State private var network = NetworkReadiness()
    @Environment(\.openURL) private var openURL
    var body: some View {
        RTCard("网络访问") {
            Label("允许无线局域网与蜂窝网络", systemImage: "network").font(.headline)
            Text("RunTick 需要网络完成登录、双端协同、时间校准和成绩保存。首次联网时，如系统询问，请选择允许使用无线局域网与蜂窝网络。")
                .font(.subheadline).foregroundStyle(RT.muted).lineSpacing(4)
            if network.checking { ProgressView("正在检测网络…") }
            Text(network.message).font(.footnote).foregroundStyle(RT.muted)
            Text("此处会访问一次 apple.com。系统是否弹窗取决于设备地区和已有授权；没有弹窗不代表未获授权。")
                .font(.caption).foregroundStyle(RT.muted)
            HStack {
                Button(network.attempted ? "重新检测" : "检测网络访问") { Task { await network.check() } }.disabled(network.checking)
                Spacer()
                Button("前往系统设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }.font(.subheadline)
        }.task(id: automaticallyCheck) {
            if automaticallyCheck && !network.attempted { await network.check() }
        }
    }
}
